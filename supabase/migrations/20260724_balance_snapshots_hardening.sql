-- Ужесточение balance_snapshots по итогам повторной проверки (ТЗ 2026-07-24, доп. проверка).
-- 1) anon может только читать демо-строки (user_id IS NULL); запись — только authenticated,
--    и только в свои строки (auth.uid() = user_id). Это отличается от остальных таблиц
--    приложения (там демо-режим разрешает анонимную запись) — сознательное исключение именно
--    для остатков семьи из-за финансовой значимости данных.
-- 2) производные суммы (total_own_money/net_balance) гарантированно согласованы с исходными
--    полями на уровне БД (Вариант B: единственная точка записи в JS + CHECK-ограничение).

drop policy if exists balance_snapshots_insert on public.balance_snapshots;
drop policy if exists balance_snapshots_update on public.balance_snapshots;
drop policy if exists balance_snapshots_delete on public.balance_snapshots;

create policy balance_snapshots_insert on public.balance_snapshots
  for insert to authenticated
  with check (auth.uid() = user_id);

create policy balance_snapshots_update on public.balance_snapshots
  for update to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy balance_snapshots_delete on public.balance_snapshots
  for delete to authenticated
  using (auth.uid() = user_id);

alter table public.balance_snapshots
  add constraint balance_snapshots_totals_check
  check (
    total_own_money = artem_amount + oksana_amount + cash_amount + other_amount
    and net_balance = total_own_money - credit_debt_amount
  );
