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
