-- Миграция 003 (уже применена): категории, рефералы с подтверждением, уведомления, запросы кода.
-- Каталог услуг и товаров загружен в базу отдельно (редактируется в кабинете мастера).
alter table public.services add column cat text not null default 'mk';
alter table public.products add column cat text not null default 'fc';
alter table public.profiles drop column ref_by;
alter table public.profiles add column ref_code text not null default substr(md5(random()::text||clock_timestamp()::text),1,8), add column inviter uuid references public.profiles(user_id) on delete set null, add column ref_status int not null default 0 check(ref_status between 0 and 2);
create unique index profiles_ref_code on public.profiles(ref_code);
create table public.notifications(id bigint generated always as identity primary key, kind text not null, user_id uuid, title text not null, read boolean not null default false, created_at timestamptz not null default now());
create table public.code_requests(id bigint generated always as identity primary key, phone text not null, name text, done boolean not null default false, created_at timestamptz not null default now());
alter table public.notifications enable row level security; alter table public.code_requests enable row level security;
create policy "master" on public.notifications for all to authenticated using (public.is_master()) with check (public.is_master());
create policy "master" on public.code_requests for all to authenticated using (public.is_master()) with check (public.is_master());
alter publication supabase_realtime add table public.notifications, public.code_requests;
-- Функции: register_profile (ищет пригласившего по ref_code и пишет уведомления), my_ref_count (только подтверждённые),
-- my_ref_pending, note_login (уведомление о входе клиента, не чаще раза в 30 мин), request_code (запрос кода, лимиты по номеру и в час).
