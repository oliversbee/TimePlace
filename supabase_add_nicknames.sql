-- ============================================================================
-- NICKNAMES
-- ============================================================================
--
-- Lets each user set their own private label for another household member —
-- e.g. Oliver sees "Dad", his sister sees "Father", for the same person.
-- Falls back to that person's real name (public.users.name) if no nickname
-- has been set.
--
-- Run this after setup_supabase.sql and supabase_add.sql.
-- ============================================================================

create table if not exists public.nicknames (
  viewer_id uuid not null references public.users(id) on delete cascade,
  target_id uuid not null references public.users(id) on delete cascade,
  nickname text not null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  primary key (viewer_id, target_id),

  constraint cannot_nickname_yourself
    check (viewer_id <> target_id)
);

create index if not exists nicknames_viewer_idx
  on public.nicknames(viewer_id);

alter table public.nicknames enable row level security;

-- A user can see, set, and remove only their own nicknames for others —
-- what Oliver calls someone is private to Oliver.

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
