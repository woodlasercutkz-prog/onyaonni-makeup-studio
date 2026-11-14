-- OnyaOnni MakeUP Studio: схема Supabase (уже применена к проекту gnhqkwdvqiqgszzoabxm)
create extension if not exists pgcrypto with schema extensions;
create table public.staff(user_id uuid primary key references auth.users on delete cascade);
create table public.settings(id int primary key default 1 check(id=1), logo int not null default 0, discount int not null default 15 check(discount between 0 and 90), off_days int[] not null default '{0}');
create table public.secrets(id int primary key default 1 check(id=1), totp text not null default encode(extensions.gen_random_bytes(20),'hex'));
insert into public.settings default values; insert into public.secrets default values;
create table public.profiles(user_id uuid primary key references auth.users on delete cascade, name text not null, phone text not null unique, ref_by text, created_at timestamptz default now());
create table public.client_notes(user_id uuid primary key references public.profiles on delete cascade, notes text not null default '');
create table public.services(id bigint generated always as identity primary key, name jsonb not null, price int not null, minutes int not null default 60, promo int, demo boolean not null default false);
create table public.products(id bigint generated always as identity primary key, name jsonb not null, price int not null, stock int not null default 0, emoji text, image_url text, demo boolean not null default false);
create table public.works(id bigint generated always as identity primary key, cat text not null, description jsonb, image_url text, emoji text, likes int not null default 0, demo boolean not null default false);
create table public.work_likes(work_id bigint references public.works on delete cascade, user_id uuid references auth.users on delete cascade, primary key(work_id,user_id));
create table public.bookings(id bigint generated always as identity primary key, user_id uuid not null default auth.uid() references auth.users on delete cascade, client_name text, service_id bigint references public.services on delete set null, day date not null, slot text not null, status int not null default 0 check(status between 0 and 3), created_at timestamptz default now());
create unique index bookings_slot on public.bookings(day,slot) where status<>3;
create table public.orders(id bigint generated always as identity primary key, user_id uuid not null default auth.uid() references auth.users on delete cascade, client_name text, items jsonb not null, total int not null, delivery boolean not null default false, status int not null default 0 check(status between 0 and 2), created_at timestamptz default now());
create table public.messages(id bigint generated always as identity primary key, thread_user uuid not null references auth.users on delete cascade, from_master boolean not null default false, body text, image_url text, read boolean not null default false, created_at timestamptz default now());
create table public.code_fails(user_id uuid not null, at timestamptz not null default now());

create function public.is_master() returns boolean language sql stable security definer set search_path=public as $$select exists(select 1 from public.staff where user_id=auth.uid())$$;
create function public.has_profile() returns boolean language sql stable security definer set search_path=public as $$select exists(select 1 from public.profiles where user_id=auth.uid())$$;
create function public._totp(off int) returns text language plpgsql security definer set search_path=public,extensions as $$
declare s text; c bigint; h bytea; o int; n bigint;
begin select totp into s from public.secrets; c:=floor(extract(epoch from now())/180)+off;
 h:=hmac(int8send(c),convert_to(s,'utf8'),'sha1'); o:=get_byte(h,19)&15;
 n:=((((get_byte(h,o)&127)::bigint)<<24)|(get_byte(h,o+1)::bigint<<16)|(get_byte(h,o+2)::bigint<<8)|get_byte(h,o+3)::bigint)%1000000;
 return lpad(n::text,6,'0'); end$$;
create function public.totp_info() returns table(code text,left_s int) language plpgsql security definer set search_path=public as $$
begin if not public.is_master() then raise exception 'forbidden'; end if;
 return query select public._totp(0),(180-(floor(extract(epoch from now()))::bigint % 180))::int; end$$;
create function public.register_profile(p_name text,p_phone text,p_ref text,p_code text) returns text language plpgsql security definer set search_path=public as $$
declare ph text:=regexp_replace(p_phone,'\D','','g'); rf text:=nullif(regexp_replace(coalesce(p_ref,''),'\D','','g'),'');
begin if auth.uid() is null then raise exception 'auth required'; end if;
 if exists(select 1 from public.profiles where user_id=auth.uid()) then return 'ok'; end if;
 if (select count(*) from public.code_fails where user_id=auth.uid() and at>now()-interval '10 minutes')>=5 then return 'locked'; end if;
 if p_code not in (public._totp(0),public._totp(-1)) then insert into public.code_fails(user_id) values(auth.uid()); return 'bad_code'; end if;
 if rf=ph then rf:=null; end if;
 insert into public.profiles(user_id,name,phone,ref_by) values(auth.uid(),left(trim(p_name),80),ph,rf); return 'ok'; end$$;
create function public.my_ref_count() returns int language sql stable security definer set search_path=public as $$select count(*)::int from public.profiles where ref_by=(select phone from public.profiles where user_id=auth.uid())$$;
create function public.discount_for_me() returns int language sql stable security definer set search_path=public as $$select case when public.my_ref_count()>=10 then (select discount from public.settings) else 0 end$$;
create function public.taken_slots(d date) returns text[] language sql stable security definer set search_path=public as $$select coalesce(array_agg(slot),'{}') from public.bookings where day=d and status<>3$$;
create function public.toggle_like(w bigint) returns void language plpgsql security definer set search_path=public as $$
begin if auth.uid() is null then raise exception 'auth required'; end if;
 if exists(select 1 from public.work_likes where work_id=w and user_id=auth.uid()) then
  delete from public.work_likes where work_id=w and user_id=auth.uid(); update public.works set likes=greatest(likes-1,0) where id=w;
 else insert into public.work_likes values(w,auth.uid()); update public.works set likes=likes+1 where id=w; end if; end$$;
create function public.place_order(p_items jsonb,p_delivery boolean) returns bigint language plpgsql security definer set search_path=public as $$
declare tot int:=0; it jsonb; pr record; q int; oid bigint; nm text;
begin if not public.has_profile() then raise exception 'no profile'; end if;
 for it in select * from jsonb_array_elements(p_items) loop
  q:=(it->>'q')::int; select * into pr from public.products where id=(it->>'id')::bigint for update;
  if not found or q<1 or pr.stock<q then raise exception 'unavailable'; end if;
  update public.products set stock=stock-q where id=pr.id; tot:=tot+pr.price*q; end loop;
 select name into nm from public.profiles where user_id=auth.uid();
 insert into public.orders(client_name,items,total,delivery) values(nm,p_items,tot*(100-public.discount_for_me())/100,p_delivery) returning id into oid; return oid; end$$;
revoke all on function public._totp(int) from public,anon,authenticated;
revoke all on function public.totp_info(),public.register_profile(text,text,text,text),public.my_ref_count(),public.discount_for_me(),public.toggle_like(bigint),public.place_order(jsonb,boolean) from public,anon;
grant execute on function public.totp_info(),public.register_profile(text,text,text,text),public.my_ref_count(),public.discount_for_me(),public.toggle_like(bigint),public.place_order(jsonb,boolean) to authenticated;

do $$ declare t text; begin
 foreach t in array array['services','products','works','settings'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('create policy "read" on public.%I for select to anon,authenticated using (true)',t);
  execute format('create policy "master" on public.%I for all to authenticated using (public.is_master()) with check (public.is_master())',t);
 end loop;
 foreach t in array array['staff','secrets','code_fails','profiles','client_notes','work_likes','bookings','orders','messages'] loop
  execute format('alter table public.%I enable row level security',t); end loop;
 foreach t in array array['profiles','client_notes','bookings','orders','messages'] loop
  execute format('create policy "master" on public.%I for all to authenticated using (public.is_master()) with check (public.is_master())',t); end loop;
end $$;
create policy "own" on public.staff for select to authenticated using (user_id=auth.uid());
create policy "own" on public.profiles for select to authenticated using (user_id=auth.uid());
create policy "own" on public.work_likes for select to authenticated using (user_id=auth.uid());
create policy "own" on public.bookings for select to authenticated using (user_id=auth.uid());
create policy "own_ins" on public.bookings for insert to authenticated with check (user_id=auth.uid() and status=0 and public.has_profile());
create policy "own" on public.orders for select to authenticated using (user_id=auth.uid());
create policy "own" on public.messages for select to authenticated using (thread_user=auth.uid());
create policy "own_ins" on public.messages for insert to authenticated with check (thread_user=auth.uid() and not from_master and public.has_profile());
alter publication supabase_realtime add table public.messages, public.bookings, public.orders;
insert into storage.buckets(id,name,public) values('media','media',true) on conflict do nothing;
create policy "media_insert" on storage.objects for insert to authenticated with check (bucket_id='media' and (public.is_master() or (storage.foldername(name))[1]=auth.uid()::text));
create policy "media_master_del" on storage.objects for delete to authenticated using (bucket_id='media' and public.is_master());

-- Мастер: после создания пользователя 77056773334@onyaonni.app в Authentication → Users
-- insert into public.staff select id from auth.users where email='77056773334@onyaonni.app';
