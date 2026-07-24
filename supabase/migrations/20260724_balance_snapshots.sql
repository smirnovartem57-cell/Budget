-- Реальные остатки семьи: ручная сверка (ТЗ 2026-07-24).
-- Каждое сохранение формы — отдельный контрольный снимок; старые не перезаписываются.
create table if not exists public.balance_snapshots (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id),
  artem_amount numeric not null default 0,
  oksana_amount numeric not null default 0,
  cash_amount numeric not null default 0,
  credit_debt_amount numeric not null default 0,
  other_amount numeric not null default 0,
  total_own_money numeric not null default 0,
  net_balance numeric not null default 0,
  comment text,
  created_by text,
  created_at timestamptz not null default now()
);
create index if not exists balance_snapshots_user_id_created_idx
  on public.balance_snapshots (user_id, created_at desc);

alter table public.balance_snapshots enable row level security;

-- Политики RLS повторяют модель остальных таблиц приложения: демо-режим (anon) работает со
-- строками user_id IS NULL, авторизованный пользователь — со своими строками.
do $$ begin
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='balance_snapshots' and policyname='balance_snapshots_select') then
    create policy balance_snapshots_select on public.balance_snapshots
      for select using (user_id is null or auth.uid() = user_id);
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='balance_snapshots' and policyname='balance_snapshots_insert') then
    create policy balance_snapshots_insert on public.balance_snapshots
      for insert with check (user_id is null or auth.uid() = user_id);
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='balance_snapshots' and policyname='balance_snapshots_update') then
    create policy balance_snapshots_update on public.balance_snapshots
      for update using (user_id is null or auth.uid() = user_id) with check (user_id is null or auth.uid() = user_id);
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='balance_snapshots' and policyname='balance_snapshots_delete') then
    create policy balance_snapshots_delete on public.balance_snapshots
      for delete using (user_id is null or auth.uid() = user_id);
  end if;
end $$;
