-- ============================================================================
-- TIMEPLACE — COMPLETE SUPABASE DATABASE SETUP
-- ============================================================================
-- Run this single file in Supabase SQL Editor on a new project.
--
-- Includes:
--   users              — one row per authenticated user
--   images             — every uploaded image
--   household          — latest image for each user
--   user_preferences   — per-user display settings
--   hidden_users       — per-user list of family members to hide
--   nicknames          — per-user private names for other family members
--   Storage            — public `posts` bucket and upload/read policies
--   RLS                — access policies for all application tables
-- ============================================================================

create extension if not exists pgcrypto;

-- ============================================================================
-- USERS
-- ============================================================================

create table if not exists public.users (
  id uuid primary key references auth.users(id) on delete cascade,
  name text,
  created_at timestamptz not null default now()
);

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

-- ============================================================================
-- IMAGES
-- ============================================================================

create table if not exists public.images (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  image_url text not null,
  taken_at timestamptz not null default now()
);

create index if not exists images_user_taken_idx
  on public.images(user_id, taken_at desc);

-- ============================================================================
-- HOUSEHOLD — latest image for each user
-- ============================================================================

create table if not exists public.household (
  user_id uuid primary key references public.users(id) on delete cascade,
  recent_image_url text,
  recent_taken_at timestamptz,
  updated_at timestamptz not null default now()
);

create or replace function public.update_household_recent_image()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.household (
    user_id,
    recent_image_url,
    recent_taken_at,
    updated_at
  )
  values (
    new.user_id,
    new.image_url,
    new.taken_at,
    now()
  )
  on conflict (user_id) do update
    set recent_image_url = excluded.recent_image_url,
        recent_taken_at = excluded.recent_taken_at,
        updated_at = excluded.updated_at
    where excluded.recent_taken_at >= public.household.recent_taken_at
       or public.household.recent_taken_at is null;

  return new;
end;
$$;

drop trigger if exists on_image_inserted on public.images;
create trigger on_image_inserted
after insert on public.images
for each row execute function public.update_household_recent_image();

-- ============================================================================
-- USER PREFERENCES
-- ============================================================================

create table if not exists public.user_preferences (
  user_id uuid primary key references public.users(id) on delete cascade,
  display_name text,
  image_interval_seconds integer not null default 300,
  show_own_image boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint image_interval_positive check (image_interval_seconds > 0)
);

-- Automatically create preferences whenever a public.users row is created.
create or replace function public.create_user_preferences()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.user_preferences (user_id, display_name)
  values (new.id, new.name)
  on conflict (user_id) do nothing;

  return new;
end;
$$;

drop trigger if exists on_user_created_preferences on public.users;
create trigger on_user_created_preferences
after insert on public.users
for each row execute function public.create_user_preferences();

-- Ensure existing users have preferences.
insert into public.user_preferences (user_id, display_name)
select id, name
from public.users
on conflict (user_id) do nothing;

-- ============================================================================
-- HIDDEN USERS
-- ============================================================================

create table if not exists public.hidden_users (
  user_id uuid not null references public.users(id) on delete cascade,
  hidden_user_id uuid not null references public.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, hidden_user_id),
  constraint cannot_hide_yourself check (user_id <> hidden_user_id)
);

create index if not exists hidden_users_user_idx
  on public.hidden_users(user_id);

create index if not exists hidden_users_hidden_user_idx
  on public.hidden_users(hidden_user_id);

-- ============================================================================
-- NICKNAMES
-- ============================================================================
-- Each user's nickname for another household member is private to that user.

create table if not exists public.nicknames (
  viewer_id uuid not null references public.users(id) on delete cascade,
  target_id uuid not null references public.users(id) on delete cascade,
  nickname text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (viewer_id, target_id),
  constraint cannot_nickname_yourself check (viewer_id <> target_id)
);

create index if not exists nicknames_viewer_idx
  on public.nicknames(viewer_id);

-- ============================================================================
-- ROW LEVEL SECURITY
-- ============================================================================

alter table public.users enable row level security;
alter table public.images enable row level security;
alter table public.household enable row level security;
alter table public.user_preferences enable row level security;
alter table public.hidden_users enable row level security;
alter table public.nicknames enable row level security;

-- Remove existing policies so this complete script can be safely re-run.
drop policy if exists "Users can view all users" on public.users;
drop policy if exists "Users can insert their own images" on public.images;
drop policy if exists "Users can view all images" on public.images;
drop policy if exists "Users can view the household table" on public.household;

drop policy if exists "Users can view their own preferences" on public.user_preferences;
drop policy if exists "Users can insert their own preferences" on public.user_preferences;
drop policy if exists "Users can update their own preferences" on public.user_preferences;
drop policy if exists "Users can delete their own preferences" on public.user_preferences;

drop policy if exists "Users can view their hidden users" on public.hidden_users;
drop policy if exists "Users can hide family members" on public.hidden_users;
drop policy if exists "Users can unhide family members" on public.hidden_users;

drop policy if exists "Users can view their own nicknames" on public.nicknames;
drop policy if exists "Users can set their own nicknames" on public.nicknames;
drop policy if exists "Users can update their own nicknames" on public.nicknames;
drop policy if exists "Users can remove their own nicknames" on public.nicknames;

-- USERS
create policy "Users can view all users"
  on public.users for select
  using (true);

-- IMAGES
create policy "Users can insert their own images"
  on public.images for insert
  with check (auth.uid() = user_id);

create policy "Users can view all images"
  on public.images for select
  using (true);

-- HOUSEHOLD
create policy "Users can view the household table"
  on public.household for select
  using (true);

-- USER PREFERENCES
create policy "Users can view their own preferences"
  on public.user_preferences for select
  using (auth.uid() = user_id);

create policy "Users can insert their own preferences"
  on public.user_preferences for insert
  with check (auth.uid() = user_id);

create policy "Users can update their own preferences"
  on public.user_preferences for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "Users can delete their own preferences"
  on public.user_preferences for delete
  using (auth.uid() = user_id);

-- HIDDEN USERS
create policy "Users can view their hidden users"
  on public.hidden_users for select
  using (auth.uid() = user_id);

create policy "Users can hide family members"
  on public.hidden_users for insert
  with check (auth.uid() = user_id);

create policy "Users can unhide family members"
  on public.hidden_users for delete
  using (auth.uid() = user_id);

-- NICKNAMES
create policy "Users can view their own nicknames"
  on public.nicknames for select
  using (auth.uid() = viewer_id);

create policy "Users can set their own nicknames"
  on public.nicknames for insert
  with check (auth.uid() = viewer_id);

create policy "Users can update their own nicknames"
  on public.nicknames for update
  using (auth.uid() = viewer_id)
  with check (auth.uid() = viewer_id);

create policy "Users can remove their own nicknames"
  on public.nicknames for delete
  using (auth.uid() = viewer_id);

-- ============================================================================
-- STORAGE
-- ============================================================================

insert into storage.buckets (id, name, public)
values ('posts', 'posts', true)
on conflict (id) do nothing;

drop policy if exists "Users can upload to their own folder" on storage.objects;
drop policy if exists "Public read access to post images" on storage.objects;

create policy "Users can upload to their own folder"
  on storage.objects for insert
  with check (
    bucket_id = 'posts'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

create policy "Public read access to post images"
  on storage.objects for select
  using (bucket_id = 'posts');

-- ============================================================================
-- END OF TIMEPLACE SUPABASE SETUP
-- ============================================================================
