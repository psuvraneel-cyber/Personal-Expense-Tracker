// Firestore security rules tests (audit P1-9 / P2-20).
// Run: npm test   (starts the Firestore emulator, then runs these tests)
import test, { before, after, beforeEach } from "node:test";
import { readFileSync } from "node:fs";
import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} from "@firebase/rules-unit-testing";
import {
  doc, setDoc, getDoc, getDocs, deleteDoc, updateDoc, collection, addDoc, query, where,
  arrayUnion, arrayRemove, deleteField, Timestamp,
} from "firebase/firestore";

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
const carol = () => env.authenticatedContext("carol").firestore();

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
  await assertFails(setDoc(doc(alice(), "users/alice/transactions/t3"), { ...txn, type: "loan" }));
});

test("transfers between own accounts are accepted", async () => {
  await assertSucceeds(setDoc(doc(alice(), "users/alice/transactions/t4"),
    { ...txn, type: "transfer", categoryId: "cat_transfer" }));
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

// ── Schema validation (audit P2-1) ─────────────────────────────────────────

test("profile and sub-collections reject unknown or oversized fields", async () => {
  await assertSucceeds(setDoc(doc(alice(), "users/alice"),
    { displayName: "Alice", email: "a@example.com", syncVersion: 1 }));
  await assertFails(setDoc(doc(alice(), "users/alice"), { isPremium: true }, { merge: true }));
  await assertFails(setDoc(doc(alice(), "users/alice/categories/c1"), { junk: "y".repeat(900000) }));
  await assertFails(setDoc(doc(alice(), "users/alice/categories/c2"),
    { id: "c2", name: "x".repeat(101), isCustom: true }));
  await assertSucceeds(setDoc(doc(alice(), "users/alice/categories/c3"),
    { id: "c3", name: "Pets", iconCodePoint: 1, colorValue: 2, isCustom: true, type: "expense" }));
});

test("transactions need a timestamp date, sane amount and known fields", async () => {
  await assertFails(setDoc(doc(alice(), "users/alice/transactions/t1"),
    { ...txn, date: "not-a-date" }));
  await assertFails(setDoc(doc(alice(), "users/alice/transactions/t2"), { ...txn, amount: 1e300 }));
  await assertFails(setDoc(doc(alice(), "users/alice/transactions/t3"), { ...txn, extra: 1 }));
  await assertFails(setDoc(doc(alice(), "users/alice/transactions/t4"), { ...txn, categoryId: 42 }));
  await assertSucceeds(setDoc(doc(alice(), "users/alice/transactions/t5"),
    { ...txn, note: "Lunch", merchantName: "Swiggy", source: "sms", updatedAt: new Date() }));
});

test("documents written by older app versions (extra fields) still update", async () => {
  await env.withSecurityRulesDisabled((ctx) =>
    setDoc(doc(ctx.firestore(), "users/alice/transactions/legacy"), { ...txn, legacyField: "x" }));
  await assertSucceeds(updateDoc(doc(alice(), "users/alice/transactions/legacy"),
    { amount: 300, updatedAt: new Date() }));
  await assertFails(updateDoc(doc(alice(), "users/alice/transactions/legacy"), { newJunk: 1 }));
});

test("legacy collections are read/delete only", async () => {
  await assertFails(setDoc(doc(alice(), "users/alice/linked_accounts/a"), { x: 1 }));
  await assertFails(setDoc(doc(alice(), "users/alice/family_members/a"), { x: 1 }));
});

test("top-level collections outside users/ are denied", async () => {
  await assertFails(setDoc(doc(alice(), "global/x"), { a: 1 }));
});

// ── Shared household budgets ────────────────────────────────────────────────

const household = {
  name: "Home",
  ownerUid: "alice",
  memberUids: ["alice"],
  memberNames: { alice: "Alice" },
  createdAt: new Date(),
};
const inDays = (d) => Timestamp.fromMillis(Date.now() + d * 86400000);

async function seedHousehold({ members = ["alice"], invite = "ABCD2345", expires = 7 } = {}) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, "households/h1"), {
      ...household,
      memberUids: members,
      memberNames: Object.fromEntries(members.map((m) => [m, m])),
    });
    if (invite) {
      await setDoc(doc(db, `householdInvites/${invite}`), {
        householdId: "h1", createdBy: "alice", expiresAt: inDays(expires),
      });
    }
  });
}

test("households: create only yourself as sole owner/member", async () => {
  await assertSucceeds(setDoc(doc(alice(), "households/h1"), household));
  await assertFails(setDoc(doc(alice(), "households/h2"),
    { ...household, memberUids: ["alice", "bob"], memberNames: { alice: "A", bob: "B" } }));
  await assertFails(setDoc(doc(bob(), "households/h3"), household));
});

test("households: guests (anonymous accounts) can't create one", async () => {
  const guest = env.authenticatedContext("guest1",
    { firebase: { sign_in_provider: "anonymous" } }).firestore();
  await assertFails(setDoc(doc(guest, "households/h9"),
    { ...household, ownerUid: "guest1", memberUids: ["guest1"], memberNames: { guest1: "G" } }));
});

test("households: owner can revoke any invite, so a removed member can't re-join", async () => {
  await seedHousehold({ members: ["alice", "bob"], invite: null });
  await env.withSecurityRulesDisabled((ctx) =>
    setDoc(doc(ctx.firestore(), "householdInvites/BOBC2345"),
      { householdId: "h1", createdBy: "bob", expiresAt: inDays(6) }));
  // Owner finds and deletes every code for the household.
  await assertSucceeds(getDocs(query(collection(alice(), "householdInvites"),
    where("householdId", "==", "h1"))));
  await assertSucceeds(deleteDoc(doc(alice(), "householdInvites/BOBC2345")));
  // Non-owners still can't list or delete other people's codes.
  await env.withSecurityRulesDisabled((ctx) =>
    setDoc(doc(ctx.firestore(), "householdInvites/ALIC2345"),
      { householdId: "h1", createdBy: "alice", expiresAt: inDays(6) }));
  await assertFails(deleteDoc(doc(bob(), "householdInvites/ALIC2345")));
  await assertFails(getDocs(query(collection(bob(), "householdInvites"),
    where("householdId", "==", "h1"))));
});

test("household spending rejects negative totals", async () => {
  await seedHousehold({ members: ["alice", "bob"] });
  await assertFails(setDoc(doc(bob(), "households/h1/spending/bob_202611"), {
    uid: "bob", month: "2026-11", byCategory: { food: 10 }, names: { food: "Food" },
    total: -5, updatedAt: new Date(),
  }));
});

test("households: only members can read; members can find theirs by query", async () => {
  await seedHousehold();
  await assertSucceeds(getDoc(doc(alice(), "households/h1")));
  await assertFails(getDoc(doc(bob(), "households/h1")));
  await assertSucceeds(getDocs(query(collection(alice(), "households"),
    where("memberUids", "array-contains", "alice"))));
});

test("households: join only yourself, only with a valid invite", async () => {
  await seedHousehold();
  const join = (db, uid, code) => updateDoc(doc(db, "households/h1"), {
    memberUids: arrayUnion(uid), [`memberNames.${uid}`]: uid, lastInviteCode: code,
  });
  await assertFails(join(bob(), "bob", "ZZZZZZZZ"));
  await assertFails(join(bob(), "carol", "ABCD2345")); // can't add someone else
  await assertSucceeds(join(bob(), "bob", "ABCD2345"));
  await assertSucceeds(getDoc(doc(bob(), "households/h1")));
});

test("households: expired invites don't work", async () => {
  await seedHousehold({ expires: -1 });
  await assertFails(updateDoc(doc(bob(), "households/h1"), {
    memberUids: arrayUnion("bob"), "memberNames.bob": "Bob", lastInviteCode: "ABCD2345",
  }));
});

test("households: members leave themselves; only the owner removes others", async () => {
  await seedHousehold({ members: ["alice", "bob", "carol"] });
  await assertFails(updateDoc(doc(bob(), "households/h1"),
    { memberUids: arrayRemove("carol"), "memberNames.carol": deleteField() }));
  await assertSucceeds(updateDoc(doc(bob(), "households/h1"),
    { memberUids: arrayRemove("bob"), "memberNames.bob": deleteField() }));
  await assertSucceeds(updateDoc(doc(alice(), "households/h1"),
    { memberUids: arrayRemove("carol"), "memberNames.carol": deleteField() }));
  await assertFails(deleteDoc(doc(carol(), "households/h1")));
  await assertSucceeds(deleteDoc(doc(alice(), "households/h1")));
});

test("household budgets: members write valid budgets; outsiders can't read", async () => {
  await seedHousehold({ members: ["alice", "bob"] });
  const budget = { categoryId: "food", categoryName: "Food", amount: 8000,
    updatedBy: "bob", updatedAt: new Date() };
  await assertSucceeds(setDoc(doc(bob(), "households/h1/budgets/food"), budget));
  await assertFails(setDoc(doc(bob(), "households/h1/budgets/food"), { ...budget, amount: -1 }));
  await assertFails(setDoc(doc(bob(), "households/h1/budgets/food"), { ...budget, updatedBy: "alice" }));
  await assertFails(getDoc(doc(carol(), "households/h1/budgets/food")));
});

test("household spending: you can only publish your own totals", async () => {
  await seedHousehold({ members: ["alice", "bob"] });
  const mine = { uid: "bob", month: "2026-10", byCategory: { food: 1200 },
    names: { food: "Food" }, total: 1200, updatedAt: new Date() };
  await assertSucceeds(setDoc(doc(bob(), "households/h1/spending/bob_202610"), mine));
  await assertFails(setDoc(doc(bob(), "households/h1/spending/alice_202610"), { ...mine, uid: "alice" }));
  await assertFails(setDoc(doc(bob(), "households/h1/spending/bob_202610"), { ...mine, txns: [] }));
  await assertSucceeds(getDoc(doc(alice(), "households/h1/spending/bob_202610")));
  await assertFails(getDoc(doc(carol(), "households/h1/spending/bob_202610")));
});

test("household invites: members create short-lived codes; anyone signed in can look one up", async () => {
  await seedHousehold({ members: ["alice"], invite: null });
  await assertSucceeds(setDoc(doc(alice(), "householdInvites/QWER2345"),
    { householdId: "h1", createdBy: "alice", expiresAt: inDays(7) }));
  await assertFails(setDoc(doc(alice(), "householdInvites/QWER2346"),
    { householdId: "h1", createdBy: "alice", expiresAt: inDays(30) }));
  await assertFails(setDoc(doc(bob(), "householdInvites/QWER2347"),
    { householdId: "h1", createdBy: "bob", expiresAt: inDays(7) }));
  await assertSucceeds(getDoc(doc(bob(), "householdInvites/QWER2345")));
  await assertFails(getDocs(collection(bob(), "householdInvites")));
});
