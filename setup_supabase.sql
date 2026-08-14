-- Run this in your Supabase project's SQL editor (Database -> SQL Editor).
--
-- Minimal schema for a single household of a fixed set of users:
--   users     — one row per person (mirrors auth.users)
--   images    — every photo uploaded (user, image_url, when)
--   household — one row per user, always pointing at their most recent image.
--               Kept up to date automatically by a trigger on `images`, so a
--               pull script can just read this table directly instead of
--               computing "latest per user" itself.
--
-- Location is intentionally left out for now — easy to add later with:
-- `alter table public.images add column latitude double precision,
--  add column longitude double precision, add column place_name text;`

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- users
-- ---------------------------------------------------------------------------
create table if not exists public.users (
  id uuid primary key references auth.users(id) on delete cascade,
  name text,
  created_at timestamptz not null default now()
);

-- Automatically creates a public.users row whenever an account is added in
-- Authentication -> Users, so you don't have to insert it by hand.
create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.users (id, name)
  values (new.id, new.email)
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_auth_user();

-- ---------------------------------------------------------------------------
-- images — every photo, one row per image (a "Both" capture uploads 2 rows)
-- ---------------------------------------------------------------------------
create table if not exists public.images (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  image_url text not null,
  taken_at timestamptz not null default now()
);

create index if not exists images_user_taken_idx
  on public.images(user_id, taken_at desc);

-- ---------------------------------------------------------------------------
-- household — one row per user, always the most recent image
-- ---------------------------------------------------------------------------
create table if not exists public.household (
  user_id uuid primary key references public.users(id) on delete cascade,
  recent_image_url text,
  recent_taken_at timestamptz,
  updated_at timestamptz not null default now()
);

-- Keeps `household` current automatically on every image insert.
create or replace function public.update_household_recent_image()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.household (user_id, recent_image_url, recent_taken_at, updated_at)
  values (new.user_id, new.image_url, new.taken_at, now())
  on conflict (user_id) do update
    set recent_image_url = excluded.recent_image_url,
        recent_taken_at = excluded.recent_taken_at,
        updated_at = excluded.updated_at
    -- Only overwrite if this image is actually newer (handles out-of-order inserts).
    where excluded.recent_taken_at >= public.household.recent_taken_at
       or public.household.recent_taken_at is null;
  return new;
end;
$$;

drop trigger if exists on_image_inserted on public.images;
create trigger on_image_inserted
  after insert on public.images
  for each row execute function public.update_household_recent_image();

-- ---------------------------------------------------------------------------
-- Row Level Security — the app inserts as itself; the pull script should use
-- the service_role key (which bypasses RLS entirely), never the anon key.
-- ---------------------------------------------------------------------------
alter table public.users enable row level security;
alter table public.images enable row level security;
alter table public.household enable row level security;

create policy "Users can view all users"
  on public.users for select
  using (true);

create policy "Users can insert their own images"
  on public.images for insert
  with check (auth.uid() = user_id);

create policy "Users can view all images"
  on public.images for select
  using (true);

create policy "Users can view the household table"
  on public.household for select
  using (true);

-- ---------------------------------------------------------------------------
-- Storage
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('posts', 'posts', true)
on conflict (id) do nothing;

create policy "Users can upload to their own folder"
  on storage.objects for insert
  with check (
    bucket_id = 'posts'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

create policy "Public read access to post images"
  on storage.objects for select
  using (bucket_id = 'posts');
