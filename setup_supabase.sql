-- Run this in your Supabase project's SQL editor (Database -> SQL Editor).

create extension if not exists pgcrypto;

create table if not exists public.posts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  image_url text not null,
  taken_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

alter table public.posts enable row level security;

create policy "Users can insert their own posts"
  on public.posts for insert
  with check (auth.uid() = user_id);

create policy "Users can view their own posts"
  on public.posts for select
  using (auth.uid() = user_id);

-- Storage bucket the app uploads photos into.
insert into storage.buckets (id, name, public)
values ('posts', 'posts', true)
on conflict (id) do nothing;

-- Files are stored as "{user_id}/{uuid}.jpg", so this policy checks that the
-- first path segment matches the uploading user's id.
create policy "Users can upload to their own folder"
  on storage.objects for insert
  with check (
    bucket_id = 'posts'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

create policy "Public read access to post images"
  on storage.objects for select
  using (bucket_id = 'posts');
