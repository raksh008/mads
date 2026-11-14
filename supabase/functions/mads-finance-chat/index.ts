const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};

function jsonResponse(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: corsHeaders });
}

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return jsonResponse({ error: "Method not allowed." }, 405);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? Deno.env.get("SUPABASE_PUBLISHABLE_KEY");
  const authorization = request.headers.get("authorization");
  if (!supabaseUrl || !supabaseAnonKey || !authorization?.startsWith("Bearer ")) {
    return jsonResponse({ error: "Sign in to start a finance conversation." }, 401);
  }

  try {
    const authResponse = await fetch(`${supabaseUrl.replace(/\/$/, "")}/auth/v1/user`, {
      headers: { apikey: supabaseAnonKey, authorization },
    });
    if (!authResponse.ok) {
      return jsonResponse({ error: "Your sign-in session could not be verified." }, 401);
    }

    const body = await request.json();
    const financialContext = body?.financialContext;
    const inputMessages = body?.messages;
    if (!financialContext || typeof financialContext !== "object" || !Array.isArray(inputMessages)) {
      return jsonResponse({ error: "The finance conversation request is invalid." }, 400);
    }

    const messages = inputMessages.slice(-17).map((message: Record<string, unknown>) => {
      if (
        !message ||
        !["user", "assistant"].includes(String(message.role)) ||
        typeof message.content !== "string" ||
        message.content.length > 2000
      ) {
        throw new Error("Invalid conversation message.");
      }
      return { role: message.role, content: message.content };
    });
    if (!messages.some((message: { role: string }) => message.role === "user")) {
      return jsonResponse({ error: "Send a message to begin." }, 400);
    }

    const endpoint = Deno.env.get("AI_CHAT_COMPLETIONS_URL");
    const apiKey = Deno.env.get("AI_API_KEY");
    const model = Deno.env.get("AI_MODEL");
    if (!endpoint || !apiKey || !model) {
      return jsonResponse({ error: "The finance companion is not connected yet." }, 503);
    }

    const systemMessage = [
      "You are Money Angel, a calm, knowledgeable personal finance companion.",
      "Speak naturally and warmly. Do not sound like a form or a bank notice.",
      "Use the supplied financial context as the only source of personal financial facts.",
      "All financial figures and affordability results in that context were computed by the app. Never calculate, estimate, round, infer, or invent a financial figure. Quote only supplied figures. If a requested figure is not supplied, say it is not available and ask only for the missing detail if needed.",
      "Never treat the difference between monthly income and the balance snapshot as spending. The balance is a dated snapshot; posted transactions on or before it are already reflected. The savings target is a planning goal, not savings achieved, and it is not deducted from safe-to-spend. Do not claim unpaid commitments or actual savings progress are known when the context says they are not tracked.",
      "Explain what records support an answer and be clear when transaction history is incomplete. Do not pressure the user to explain the income-to-balance difference. Do not repeat questions the user has already answered.",
      `Verified financial context: ${JSON.stringify(financialContext)}`,
    ].join("\n\n");

    const aiResponse = await fetch(endpoint, {
      method: "POST",
      headers: {
        authorization: `Bearer ${apiKey}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        model,
        temperature: 0.4,
        messages: [{ role: "system", content: systemMessage }, ...messages],
      }),
    });
    if (!aiResponse.ok) {
      console.error("Money Angel AI provider returned", aiResponse.status);
      return jsonResponse({ error: "The finance companion is temporarily unavailable." }, 502);
    }

    const completion = await aiResponse.json();
    const reply = completion?.choices?.[0]?.message?.content;
    if (typeof reply !== "string" || !reply.trim()) {
      return jsonResponse({ error: "The finance companion returned an empty reply." }, 502);
    }
    return jsonResponse({ reply: reply.trim() });
  } catch (error) {
    console.error("Money Angel finance chat request failed", error);
    return jsonResponse({ error: "The finance companion is temporarily unavailable." }, 502);
  }
});
