# F5 — Push-напоминания о платежах: установка

Клиентская часть (service worker, подписка, кнопка «Напоминания» в шапке) уже в проде.
Чтобы напоминания реально приходили, нужно один раз настроить серверную часть Supabase.
Все шаги ниже выполняются в панели Supabase — приватный VAPID-ключ в репозиторий не
коммитится.

## 1. Таблица подписок — ✅ ГОТОВО

Таблица `push_subscriptions` (с RLS) уже создана в проекте. SQL сохранён в
`supabase/migrations/20260717_push_subscriptions.sql` для истории.

## 2. Секреты Edge Function (VAPID)

Project Settings → Edge Functions → Secrets → добавьте:

| Имя | Значение |
|-----|----------|
| `VAPID_PUBLIC_KEY` | `BIJ18JyllgjqyHjXXOZB2ri_F1PRglZAaacUBpPrAKwGEBnPVRWY6cgmbnfVu8FcrdSjEqH-lZ6F0PCFgzxcAdM` |
| `VAPID_PRIVATE_KEY` | *(приватный ключ — см. чат, где я его прислал; в репозиторий не коммитим)* |
| `VAPID_SUBJECT` | `mailto:smirnovartem57@gmail.com` |

Публичный ключ уже вшит в клиент (`VAPID_PUBLIC_KEY` в `index.html`). Он должен совпадать
со значением секрета. `SUPABASE_URL` и `SUPABASE_SERVICE_ROLE_KEY` функции доступны
автоматически — их добавлять не нужно.

## 3. Деплой Edge Function — ✅ ГОТОВО

Функция `send-payment-reminders` задеплоена (status ACTIVE, version 1, **verify_jwt: true**).
Код — в `supabase/functions/send-payment-reminders/index.ts`. Т.к. включена проверка JWT,
вызывающий (cron ниже) обязан передавать `Authorization: Bearer <SERVICE_ROLE_KEY>` —
это уже учтено в примере cron. Повторный деплой при изменениях:
`supabase functions deploy send-payment-reminders`.

## 4. Расписание (cron)

Ежедневный запуск, например в 10:00. В SQL Editor (нужны расширения `pg_cron` и `pg_net`):

```sql
create extension if not exists pg_cron;
create extension if not exists pg_net;

select cron.schedule(
  'payment-reminders-daily',
  '0 10 * * *',
  $$
  select net.http_post(
    url := 'https://ycjomrlzqoftrudfrnbk.supabase.co/functions/v1/send-payment-reminders',
    headers := jsonb_build_object('Authorization', 'Bearer <SERVICE_ROLE_KEY>', 'Content-Type', 'application/json')
  );
  $$
);
```

Замените `<SERVICE_ROLE_KEY>` на service-role ключ проекта. (Альтернатива — вкладка
Edge Functions → Schedules в панели Supabase, если она доступна в вашем плане.)

## 5. Проверка

1. Откройте finance.smirart.ru как установленное PWA, войдите в аккаунт.
2. Нажмите «Напоминания» в шапке → разрешите уведомления. В `push_subscriptions`
   появится строка.
3. Вызовите функцию вручную (Edge Functions → send-payment-reminders → Invoke, или
   `curl` с Bearer service-role) — при наличии платежей на сегодня/завтра придёт push.

## Примечания

- iOS: web-push работает только для PWA, добавленного на домашний экран (iOS 16.4+).
- Мёртвые подписки (404/410) функция удаляет автоматически.
- Ротация VAPID: при смене ключей обновите и секрет, и `VAPID_PUBLIC_KEY` в `index.html`,
  и переподпишите клиентов.
