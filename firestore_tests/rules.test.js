// Firestore security rules tests (audit P1-9 / P2-20).
// Run: npm test   (starts the Firestore emulator, then runs these tests)
import test, { before, after, beforeEach } from "node:test";
import { readFileSync } from "node:fs";
import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} from "@firebase/rules-unit-testing";
import { doc, setDoc, getDoc, deleteDoc, collection, addDoc } from "firebase/firestore";

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: "demo-pet",
    firestore: { rules: readFileSync(new URL("../firestore.rules", import.meta.url), "utf8") },
  });
});
after(async () => env?.cleanup());
beforeEach(async () => env.clearFirestore());

const alice = () => env.authenticatedContext("alice").firestore();
const bob = () => env.authenticatedContext("bob").firestore();
const anon = () => env.unauthenticatedContext().firestore();

const txn = { amount: 250, type: "expense", categoryId: "food", date: new Date() };

test("owner can write and read own transaction", async () => {
  await assertSucceeds(setDoc(doc(alice(), "users/alice/transactions/t1"), txn));
  await assertSucceeds(getDoc(doc(alice(), "users/alice/transactions/t1")));
});

test("other users and signed-out clients cannot access it", async () => {
  await env.withSecurityRulesDisabled((ctx) =>
    setDoc(doc(ctx.firestore(), "users/alice/transactions/t1"), txn));
  await assertFails(getDoc(doc(bob(), "users/alice/transactions/t1")));
  await assertFails(setDoc(doc(bob(), "users/alice/transactions/t2"), txn));
  await assertFails(getDoc(doc(anon(), "users/alice/transactions/t1")));
});

test("invalid transactions are rejected (non-positive, NaN, bad type)", async () => {
  await assertFails(setDoc(doc(alice(), "users/alice/transactions/t1"), { ...txn, amount: 0 }));
  await assertFails(setDoc(doc(alice(), "users/alice/transactions/t2"), { ...txn, amount: NaN }));
  await assertFails(setDoc(doc(alice(), "users/alice/transactions/t3"), { ...txn, type: "transfer" }));
});

test("weekly_limits and recurring_payment_history are writable by owner (P1-9)", async () => {
  await assertSucceeds(setDoc(doc(alice(), "users/alice/weekly_limits/w1"),
    { id: "w1", categoryId: "food", categoryName: "Food", weeklyLimit: 1000 }));
  await assertSucceeds(setDoc(doc(alice(), "users/alice/recurring_payment_history/h1"),
    { id: "h1", recurringPaymentId: "r1", amount: 499 }));
  await assertFails(setDoc(doc(bob(), "users/alice/weekly_limits/w2"),
    { weeklyLimit: 1 }));
});

test("ai_reports: owner can create a well-formed report only", async () => {
  const report = { reply: "x", prompt: "y", reason: "Offensive or harmful", createdAt: new Date() };
  await assertSucceeds(addDoc(collection(alice(), "users/alice/ai_reports"), report));
  await assertFails(addDoc(collection(alice(), "users/alice/ai_reports"), { ...report, extra: 1 }));
  await assertFails(addDoc(collection(bob(), "users/alice/ai_reports"), report));
});

test("owner can delete anything under their tree (account deletion)", async () => {
  await env.withSecurityRulesDisabled((ctx) =>
    setDoc(doc(ctx.firestore(), "users/alice/legacy_stuff/x"), { a: 1 }));
  await assertSucceeds(deleteDoc(doc(alice(), "users/alice/legacy_stuff/x")));
});

test("top-level collections outside users/ are denied", async () => {
  await assertFails(setDoc(doc(alice(), "global/x"), { a: 1 }));
});
