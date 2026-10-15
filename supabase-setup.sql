-- Lamma Tleta: shared app database and private image storage
-- Run the whole script once in Supabase Dashboard > SQL Editor.
-- Keep public sign-ups disabled. Create the three friends' accounts in Authentication > Users.

create extension if not exists pgcrypto;

create table if not exists public.friend_messages (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references auth.users(id) on delete cascade,
  author_name text not null default 'صاحبنا',
  body text not null check (char_length(body) between 1 and 1000),
  created_at timestamptz not null default now()
);

create table if not exists public.friend_memories (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references auth.users(id) on delete cascade,
  author_name text not null default 'صاحبنا',
  title text not null check (char_length(title) between 1 and 100),
  note text check (note is null or char_length(note) <= 500),
  image_path text,
  created_at timestamptz not null default now()
);

create table if not exists public.friend_outings (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references auth.users(id) on delete cascade,
  author_name text not null default 'صاحبنا',
  title text not null check (char_length(title) between 1 and 120),
  place text check (place is null or char_length(place) <= 120),
  starts_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.friend_settings (
  id integer primary key check (id = 1),
  cover_path text,
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now()
);

insert into public.friend_settings (id) values (1) on conflict (id) do nothing;

alter table public.friend_messages enable row level security;
alter table public.friend_memories enable row level security;
alter table public.friend_outings enable row level security;
alter table public.friend_settings enable row level security;

grant select, insert, delete on public.friend_messages to authenticated;
grant select, insert, delete on public.friend_memories to authenticated;
grant select, insert, delete on public.friend_outings to authenticated;
grant select, insert, update on public.friend_settings to authenticated;

drop policy if exists "friends read messages" on public.friend_messages;
create policy "friends read messages" on public.friend_messages for select to authenticated using (auth.uid() is not null);
drop policy if exists "friends add own messages" on public.friend_messages;
create policy "friends add own messages" on public.friend_messages for insert to authenticated with check (author_id = auth.uid());
drop policy if exists "friends delete own messages" on public.friend_messages;
create policy "friends delete own messages" on public.friend_messages for delete to authenticated using (author_id = auth.uid());

drop policy if exists "friends read memories" on public.friend_memories;
create policy "friends read memories" on public.friend_memories for select to authenticated using (auth.uid() is not null);
drop policy if exists "friends add own memories" on public.friend_memories;
create policy "friends add own memories" on public.friend_memories for insert to authenticated with check (author_id = auth.uid());
drop policy if exists "friends delete own memories" on public.friend_memories;
create policy "friends delete own memories" on public.friend_memories for delete to authenticated using (author_id = auth.uid());

drop policy if exists "friends read outings" on public.friend_outings;
create policy "friends read outings" on public.friend_outings for select to authenticated using (auth.uid() is not null);
drop policy if exists "friends add own outings" on public.friend_outings;
create policy "friends add own outings" on public.friend_outings for insert to authenticated with check (author_id = auth.uid());
drop policy if exists "friends delete own outings" on public.friend_outings;
create policy "friends delete own outings" on public.friend_outings for delete to authenticated using (author_id = auth.uid());

drop policy if exists "friends read settings" on public.friend_settings;
create policy "friends read settings" on public.friend_settings for select to authenticated using (auth.uid() is not null);
drop policy if exists "friends add settings" on public.friend_settings;
create policy "friends add settings" on public.friend_settings for insert to authenticated with check (id = 1);
drop policy if exists "friends update settings" on public.friend_settings;
create policy "friends update settings" on public.friend_settings for update to authenticated using (id = 1) with check (id = 1);

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('lamma-media', 'lamma-media', false, 8388608, array['image/jpeg','image/png','image/webp','image/gif'])
on conflict (id) do update set public = false, file_size_limit = 8388608, allowed_mime_types = array['image/jpeg','image/png','image/webp','image/gif'];

drop policy if exists "friends view lamma images" on storage.objects;
create policy "friends view lamma images" on storage.objects for select to authenticated using (bucket_id = 'lamma-media');
drop policy if exists "friends upload own lamma images" on storage.objects;
create policy "friends upload own lamma images" on storage.objects for insert to authenticated with check (bucket_id = 'lamma-media' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists "friends delete own lamma images" on storage.objects;
create policy "friends delete own lamma images" on storage.objects for delete to authenticated using (bucket_id = 'lamma-media' and (storage.foldername(name))[1] = auth.uid()::text);

do $$
begin
  alter publication supabase_realtime add table public.friend_messages;
exception when duplicate_object then null;
end $$;
do $$
begin
  alter publication supabase_realtime add table public.friend_memories;
exception when duplicate_object then null;
end $$;
do $$
begin
  alter publication supabase_realtime add table public.friend_outings;
exception when duplicate_object then null;
end $$;
do $$
begin
  alter publication supabase_realtime add table public.friend_settings;
exception when duplicate_object then null;
end $$;

-- Separate per-user app unlock password. The value is only stored as a bcrypt hash.
create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

create table if not exists public.app_passcodes (
  user_id uuid primary key references auth.users(id) on delete cascade,
  pass_hash text not null,
  failed_attempts integer not null default 0,
  locked_until timestamptz,
  updated_at timestamptz not null default now()
);
alter table public.app_passcodes add column if not exists failed_attempts integer not null default 0;
alter table public.app_passcodes add column if not exists locked_until timestamptz;
alter table public.app_passcodes enable row level security;
revoke all on public.app_passcodes from anon, authenticated;

create or replace function public.has_app_passcode()
returns boolean
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED' using errcode = '28000'; end if;
  return exists (select 1 from public.app_passcodes where user_id = auth.uid());
end;
$$;

create or replace function public.verify_app_passcode(p_password text)
returns boolean
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare v public.app_passcodes%rowtype; v_attempts integer;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED' using errcode = '28000'; end if;
  if p_password is null or char_length(p_password) > 128 then return false; end if;
  select * into v from public.app_passcodes where user_id = auth.uid() for update;
  if not found then return false; end if;
  if v.locked_until is not null and v.locked_until > now() then return false; end if;
  if v.pass_hash = crypt(p_password, v.pass_hash) then
    update public.app_passcodes set failed_attempts = 0, locked_until = null where user_id = auth.uid();
    return true;
  end if;
  v_attempts := case when v.locked_until is not null and v.locked_until <= now() then 1 else v.failed_attempts + 1 end;
  update public.app_passcodes set failed_attempts = v_attempts,
    locked_until = case when v_attempts >= 5 then now() + interval '15 minutes' else null end
    where user_id = auth.uid();
  return false;
end;
$$;

create or replace function public.set_app_passcode(p_password text)
returns boolean
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED' using errcode = '28000'; end if;
  if p_password is null or char_length(p_password) < 8 or char_length(p_password) > 128 then
    raise exception 'PASSWORD_LENGTH' using errcode = '22023';
  end if;
  insert into public.app_passcodes(user_id, pass_hash, failed_attempts, locked_until, updated_at)
  values(auth.uid(), crypt(p_password, gen_salt('bf', 12)), 0, null, now())
  on conflict (user_id) do nothing;
  return found;
end;
$$;

create or replace function public.change_app_passcode(p_current text, p_new text)
returns boolean
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare v public.app_passcodes%rowtype; v_attempts integer;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED' using errcode = '28000'; end if;
  if p_new is null or char_length(p_new) < 8 or char_length(p_new) > 128 then
    raise exception 'PASSWORD_LENGTH' using errcode = '22023';
  end if;
  select * into v from public.app_passcodes where user_id = auth.uid() for update;
  if not found then return false; end if;
  if v.locked_until is not null and v.locked_until > now() then return false; end if;
  if p_current is null or v.pass_hash <> crypt(p_current, v.pass_hash) then
    v_attempts := case when v.locked_until is not null and v.locked_until <= now() then 1 else v.failed_attempts + 1 end;
    update public.app_passcodes set failed_attempts = v_attempts,
      locked_until = case when v_attempts >= 5 then now() + interval '15 minutes' else null end
      where user_id = auth.uid();
    return false;
  end if;
  update public.app_passcodes set pass_hash = crypt(p_new, gen_salt('bf', 12)), failed_attempts = 0, locked_until = null, updated_at = now()
    where user_id = auth.uid();
  return true;
end;
$$;

-- Forgotten app password reset is allowed only just after the primary account re-authenticated.
create or replace function public.reset_app_passcode(p_new_password text)
returns boolean
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare v_iat bigint;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED' using errcode = '28000'; end if;
  if p_new_password is null or char_length(p_new_password) < 8 or char_length(p_new_password) > 128 then
    raise exception 'PASSWORD_LENGTH' using errcode = '22023';
  end if;
  v_iat := nullif(auth.jwt() ->> 'iat', '')::bigint;
  if v_iat is null or extract(epoch from now())::bigint - v_iat > 600 then
    raise exception 'REAUTH_REQUIRED' using errcode = '28000';
  end if;
  insert into public.app_passcodes(user_id, pass_hash, failed_attempts, locked_until, updated_at)
  values(auth.uid(), crypt(p_new_password, gen_salt('bf', 12)), 0, null, now())
  on conflict (user_id) do update set pass_hash = excluded.pass_hash, failed_attempts = 0, locked_until = null, updated_at = now();
  return true;
end;
$$;

revoke all on function public.has_app_passcode() from public, anon;
revoke all on function public.verify_app_passcode(text) from public, anon;
revoke all on function public.set_app_passcode(text) from public, anon;
revoke all on function public.change_app_passcode(text, text) from public, anon;
revoke all on function public.reset_app_passcode(text) from public, anon;
grant execute on function public.has_app_passcode() to authenticated;
grant execute on function public.verify_app_passcode(text) to authenticated;
grant execute on function public.set_app_passcode(text) to authenticated;
grant execute on function public.change_app_passcode(text, text) to authenticated;
grant execute on function public.reset_app_passcode(text) to authenticated;
