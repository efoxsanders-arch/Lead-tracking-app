// Lead Tracker: receives new leads from Google Ads lead forms, Angi / HomeAdvisor,
// Thumbtack or any other tool that can send a web request, and files them in the
// right customer's account.
//
// Address:  https://<project>.supabase.co/functions/v1/lead-intake?source=<kind>&key=<account key>
// Kinds:    google_ads, angi, thumbtack, other
// The key can also arrive as an "x-api-key" header, or as Google's "google_key" field.
//
// Deploy with "Verify JWT" turned OFF: lead vendors cannot sign in.

const KINDS = ["google_ads", "google_lsa", "angi", "thumbtack", "other"];

function text(v) {
  if (v == null) return "";
  return String(v).replace(/\s+/g, " ").trim();
}
function amount(v) {
  if (v && typeof v === "object") v = v.amount != null ? v.amount : v.value;
  const n = typeof v === "number" ? v : parseFloat(text(v).replace(/[^0-9.]/g, ""));
  return isFinite(n) && n >= 0 ? Math.round(n * 100) / 100 : null;
}
function lines(list) {
  return list.filter(Boolean).join("\n");
}

// Turns each vendor's format into one common shape.
export function mapLead(kind, b) {
  b = b && typeof b === "object" ? b : {};

  if (kind === "google_ads") {
    const cols = {}, extra = [];
    (Array.isArray(b.user_column_data) ? b.user_column_data : []).forEach((c) => {
      if (!c) return;
      const id = text(c.column_id).toUpperCase(), val = text(c.string_value);
      if (!val) return;
      cols[id] = val;
      if (["FULL_NAME", "FIRST_NAME", "LAST_NAME", "PHONE_NUMBER", "EMAIL", "WORK_EMAIL", "WORK_PHONE", "SERVICE"].indexOf(id) < 0) {
        extra.push((text(c.column_name) || id.replace(/_/g, " ").toLowerCase()) + ": " + val);
      }
    });
    return {
      key: text(b.google_key),
      lead: {
        name: cols.FULL_NAME || text([cols.FIRST_NAME, cols.LAST_NAME].join(" ")),
        phone: cols.PHONE_NUMBER || cols.WORK_PHONE || "",
        email: cols.EMAIL || cols.WORK_EMAIL || "",
        service: cols.SERVICE || "",
        notes: lines([b.is_test ? "Test lead from Google." : "", lines(extra)]),
        cost: b.is_test ? 0 : null,
        vendor_lead_id: text(b.lead_id),
      },
    };
  }

  if (kind === "angi") {
    const qa = (Array.isArray(b.interview) ? b.interview : []).map((q) => q && text(q.question) + " " + text(q.answer));
    const where = text([b.address, b.city, b.stateProvince, b.postalCode].filter(Boolean).join(", "));
    return {
      key: "",
      lead: {
        name: text(b.name) || text([b.firstName, b.lastName].join(" ")),
        phone: text(b.primaryPhone) + (text(b.phoneExt) ? " x" + text(b.phoneExt) : ""),
        email: text(b.email),
        service: text(b.taskName),
        notes: lines([text(b.comments), where, lines(qa), text(b.leadSource) ? "Came through " + text(b.leadSource) + "." : ""]),
        cost: amount(b.fee),
        vendor_lead_id: text(b.leadOid),
      },
    };
  }

  if (kind === "thumbtack") {
    let d = b.data && typeof b.data === "object" ? b.data : b;
    if (d.negotiation && typeof d.negotiation === "object") d = d.negotiation;
    const c = d.customer || {}, r = d.request || {}, loc = r.location || {};
    // Thumbtack also sends message and review events to the same address. Only leads are kept.
    if (!d.negotiationID || (!d.customer && !d.request)) return { key: "", ignore: true };
    const qa = (Array.isArray(r.details) ? r.details : []).map((q) => q && text(q.question) + ": " + text(q.answer));
    const price = [d.leadPrice, d.price, d.leadCost].map(amount).filter((n) => n != null)[0];
    return {
      key: "",
      lead: {
        name: text(c.name) || text([c.firstName, c.lastName].join(" ")),
        phone: text(c.phone),
        email: text(c.email),
        service: text(r.category && r.category.name) || text(r.title),
        notes: lines([text(r.description), text([loc.city, loc.state, loc.zipCode].filter(Boolean).join(", ")), lines(qa)]),
        cost: price == null ? null : price,
        vendor_lead_id: text(d.negotiationID),
      },
    };
  }

  return {
    key: "",
    lead: {
      name: text(b.name) || text([b.first_name || b.firstName, b.last_name || b.lastName].join(" ")),
      phone: text(b.phone),
      email: text(b.email),
      service: text(b.service),
      notes: text(b.notes || b.message),
      cost: b.cost == null ? null : amount(b.cost),
      vendor_lead_id: text(b.id || b.lead_id),
    },
  };
}

function reply(status, body) {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

export async function handle(req, env, fetchFn) {
  if (req.method === "GET" || req.method === "HEAD") return reply(200, { status: "success", message: "Lead intake is running." });
  if (req.method !== "POST") return reply(405, { status: "error", message: "Send leads with POST." });

  const url = new URL(req.url);
  let kind = text(url.searchParams.get("source")).toLowerCase();
  if (KINDS.indexOf(kind) < 0) kind = "other";

  let body;
  try { body = JSON.parse(await req.text()); } catch (_e) { return reply(400, { status: "error", message: "The lead was not valid JSON." }); }

  const mapped = mapLead(kind, body);
  const key = text(url.searchParams.get("key")) || text(req.headers.get("x-api-key")) || mapped.key;
  if (!key) return reply(401, { status: "error", message: "Missing account key." });
  if (mapped.ignore) return reply(200, { status: "success", message: "Not a lead. Ignored." });

  mapped.lead.raw = body;
  let res, out;
  try {
    res = await fetchFn(env.url + "/rest/v1/rpc/lead_intake", {
      method: "POST",
      headers: { "Content-Type": "application/json", apikey: env.key, Authorization: "Bearer " + env.key },
      body: JSON.stringify({ p_key: key, p_kind: kind, p_lead: mapped.lead }),
    });
    out = await res.json();
  } catch (_e) {
    return reply(503, { status: "error", message: "Could not save the lead. Try again." });
  }
  if (res.ok) return reply(200, { status: "success", leadId: out });
  if (out && text(out.message).indexOf("invalid_key") >= 0) return reply(401, { status: "error", message: "Unknown account key." });
  return reply(500, { status: "error", message: "Could not save the lead." });
}

// @ts-ignore: Deno exists only when this runs on Supabase.
if (typeof Deno !== "undefined") {
  // @ts-ignore
  Deno.serve((req) => handle(req, { url: Deno.env.get("SUPABASE_URL"), key: Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") }, fetch));
}
