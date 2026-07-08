export default {
  async fetch(request, env, ctx) {
    if (request.method !== "POST") {
      return new Response("Method not allowed", { status: 405 });
    }

    // 1. Verify Authorization Header
    const authHeader = request.headers.get("Authorization") || "";
    if (!authHeader.startsWith("Bearer ")) {
      return new Response(JSON.stringify({ error: "Unauthorized: Missing or invalid token" }), {
        status: 401,
        headers: { "Content-Type": "application/json" }
      });
    }

    const idToken = authHeader.replace("Bearer ", "");

    // 2. Validate with Firebase Auth REST API 
    // This is a secure, lightweight way to verify a Firebase token without huge JWT libraries.
    const verifyResp = await fetch(`https://identitytoolkit.googleapis.com/v1/accounts:lookup?key=${env.FIREBASE_WEB_API_KEY}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ idToken })
    });

    if (!verifyResp.ok) {
      return new Response(JSON.stringify({ error: "Unauthorized: Invalid Firebase token" }), {
        status: 401,
        headers: { "Content-Type": "application/json" }
      });
    }

    // 3. Read body intended for Groq
    let body;
    try {
      body = await request.json();
    } catch {
      return new Response(JSON.stringify({ error: "Invalid JSON" }), { status: 400 });
    }

    // 4. Forward to Groq
    if (!env.GROQ_API_KEY) {
      return new Response(JSON.stringify({ error: "Server error: Missing GROQ_API_KEY secret" }), {
        status: 500,
        headers: { "Content-Type": "application/json" }
      });
    }

    const groqResp = await fetch("https://api.groq.com/openai/v1/chat/completions", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${env.GROQ_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: body.model,
        messages: body.messages,
        max_tokens: body.max_tokens,
      }),
    });

    const data = await groqResp.json();

    // 5. Return Groq's response to the Flutter app
    return new Response(JSON.stringify(data), {
      status: groqResp.status,
      headers: { "Content-Type": "application/json" }
    });
  },
};
