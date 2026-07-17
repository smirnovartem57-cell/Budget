// Edge Function: send-payment-reminders (F5, 2026-07-17)
// Находит регулярные платежи и подписки, списание которых наступает сегодня/завтра,
// и рассылает web-push каждому пользователю с активной подпиской. Все суммы считаются
// детерминированным кодом. Запускается по расписанию (cron -> pg_net, см. F5_SETUP.md).
//
// Требуемые секреты функции (Project Settings -> Edge Functions -> Secrets):
//   VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY, VAPID_SUBJECT (напр. mailto:you@example.com)
// SUPABASE_URL и SUPABASE_SERVICE_ROLE_KEY доступны в окружении функции автоматически.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import webpush from "npm:web-push@3.6.7";

Deno.serve(async (_req: Request) => {
  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const vapidPublic = Deno.env.get("VAPID_PUBLIC_KEY");
  const vapidPrivate = Deno.env.get("VAPID_PRIVATE_KEY");
  const vapidSubject = Deno.env.get("VAPID_SUBJECT") || "mailto:admin@finance.smirart.ru";
  if (!vapidPublic || !vapidPrivate) {
    return new Response(JSON.stringify({ error: "VAPID keys not configured" }), { status: 500 });
  }
  webpush.setVapidDetails(vapidSubject, vapidPublic, vapidPrivate);
  const supabase = createClient(supabaseUrl, serviceKey);

  const today = new Date(); today.setHours(0, 0, 0, 0);
  const tomorrow = new Date(today); tomorrow.setDate(tomorrow.getDate() + 1);
  const iso = (d: Date) => d.toISOString().slice(0, 10);
  const todayS = iso(today), tomorrowS = iso(tomorrow);

  const { data: recTx } = await supabase.from("transactions")
    .select("user_id, category, subcategory, amount, date")
    .eq("is_recurring", true).gte("date", todayS).lte("date", tomorrowS);
  const { data: subs } = await supabase.from("subscriptions")
    .select("user_id, name, amount, next_billing_date")
    .eq("is_active", true).gte("next_billing_date", todayS).lte("next_billing_date", tomorrowS);

  const byUser = new Map<string, { name: string; amount: number; date: string }[]>();
  const add = (uid: string | null, item: { name: string; amount: number; date: string }) => {
    if (!uid) return;
    if (!byUser.has(uid)) byUser.set(uid, []);
    byUser.get(uid)!.push(item);
  };
  (recTx || []).forEach((t: any) => add(t.user_id, { name: t.subcategory ? `${t.category} · ${t.subcategory}` : t.category, amount: Number(t.amount), date: t.date }));
  (subs || []).forEach((s: any) => add(s.user_id, { name: s.name, amount: Number(s.amount), date: s.next_billing_date }));

  const fmt = (n: number) => new Intl.NumberFormat("ru-RU").format(Math.round(n)) + " ₽";
  let sent = 0, failed = 0;
  for (const [uid, items] of byUser) {
    const total = items.reduce((s, i) => s + i.amount, 0);
    const nearest = items.slice().sort((a, b) => a.date.localeCompare(b.date))[0];
    const title = "Скоро списания";
    const body = `${fmt(total)} в ближайшие дни. Ближайший: ${nearest.name} — ${fmt(nearest.amount)}, ${nearest.date.slice(8, 10)}.${nearest.date.slice(5, 7)}`;
    const payload = JSON.stringify({ title, body, url: "./", tag: "payment-reminder" });

    const { data: subsRows } = await supabase.from("push_subscriptions").select("*").eq("user_id", uid);
    for (const row of (subsRows || [])) {
      const pushSub = { endpoint: row.endpoint, keys: { p256dh: row.p256dh, auth: row.auth } };
      try {
        await webpush.sendNotification(pushSub as any, payload);
        sent++;
        await supabase.from("push_subscriptions").update({ last_notified_at: new Date().toISOString() }).eq("id", row.id);
      } catch (e: any) {
        failed++;
        if (e && (e.statusCode === 404 || e.statusCode === 410)) {
          await supabase.from("push_subscriptions").delete().eq("id", row.id);
        }
      }
    }
  }
  return new Response(JSON.stringify({ users: byUser.size, sent, failed }), { headers: { "Content-Type": "application/json" } });
});
