-- Одна сверка остатка на календарный день (ТЗ 2026-07-24, доп.).
-- Локальный календарный день (Asia/Almaty), не UTC-день — считается в приложении при создании
-- записи (localSnapshotDateStr()) и здесь при бэкофилле через AT TIME ZONE.

-- 1) добавляем snapshot_date (nullable на время бэкофилла) и updated_at.
alter table public.balance_snapshots
  add column if not exists snapshot_date date,
  add column if not exists updated_at timestamptz not null default now();

-- существующие строки: updated_at = created_at (запись ещё не редактировалась), а не момент
-- миграции — иначе старые записи ошибочно выглядели бы «только что обновлёнными».
update public.balance_snapshots set updated_at = created_at;

-- 2) бэкофилл календарной даты по локальному часовому поясу семьи.
update public.balance_snapshots
  set snapshot_date = (created_at at time zone 'Asia/Almaty')::date
  where snapshot_date is null;

-- 3) дедупликация (на случай если до появления этого ограничения где-то возникли две записи
-- за один день одного пользователя): оставляем одну запись на (user_id, snapshot_date) —
-- по последнему updated_at, при равенстве — по created_at, при равенстве — по id.
-- Не затрагивает user_id IS NULL (демо) отдельно — те же правила применяются одинаково.
with ranked as (
  select id, user_id, snapshot_date,
         row_number() over (
           partition by user_id, snapshot_date
           order by updated_at desc nulls last, created_at desc, id desc
         ) as rn
  from public.balance_snapshots
  where snapshot_date is not null
)
delete from public.balance_snapshots bs
using ranked r
where bs.id = r.id and r.rn > 1;

-- 4) закрепляем ограничение на уровне БД.
alter table public.balance_snapshots alter column snapshot_date set not null;
alter table public.balance_snapshots
  add constraint balance_snapshots_user_snapshot_date_uniq unique (user_id, snapshot_date);
