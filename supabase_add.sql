-- ============================================================================
-- USER CUSTOMISATION / DISPLAY SETTINGS
-- ============================================================================
--
-- Adds:
--   user_preferences — one preferences row per user
--   hidden_users     — which family members each user has chosen to hide
--
-- Existing tables are left unchanged:
--   users
--   images
--   household
--
-- ============================================================================


-- ---------------------------------------------------------------------------
-- user_preferences
-- ---------------------------------------------------------------------------
-- One row per user.
--
-- display_name:
--   The name shown on that user's display.
--
-- image_interval_seconds:
--   How often the e-ink display should change image.
--
-- show_own_image:
--   Whether the user wants their own photos displayed on their display.
--
-- ---------------------------------------------------------------------------

create table if not exists public.user_preferences (
  user_id uuid primary key references public.users(id) on delete cascade,

  display_name text,

  image_interval_seconds integer not null default 300,

  show_own_image boolean not null default true,

  created_at timestamptz not null default now(),

  updated_at timestamptz not null default now(),

  constraint image_interval_positive
    check (image_interval_seconds > 0)
);


-- ---------------------------------------------------------------------------
-- hidden_users
-- ---------------------------------------------------------------------------
-- Each row represents:
--
--   user_id        = person doing the hiding
--   hidden_user_id = person they don't want to see
--
-- Example:
--
--   Oliver -> Mum
--   Dad    -> Sister
--
-- This allows every user to have their own independent list.
--
-- ---------------------------------------------------------------------------

create table if not exists public.hidden_users (
  user_id uuid not null references public.users(id) on delete cascade,

  hidden_user_id uuid not null references public.users(id) on delete cascade,

  created_at timestamptz not null default now(),

  primary key (user_id, hidden_user_id),

  constraint cannot_hide_yourself
    check (user_id <> hidden_user_id)
);


-- ---------------------------------------------------------------------------
-- Indexes
-- ---------------------------------------------------------------------------

create index if not exists hidden_users_user_idx
  on public.hidden_users(user_id);

create index if not exists hidden_users_hidden_user_idx
  on public.hidden_users(hidden_user_id);


-- ---------------------------------------------------------------------------
-- Automatically create preferences for new users
-- ---------------------------------------------------------------------------
-- When a new auth user is created, your existing trigger creates their
-- public.users row.
--
-- This additional trigger creates their preferences row.
--
-- The display name initially uses the name from public.users.
-- ---------------------------------------------------------------------------

create or replace function public.create_user_preferences()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.user_preferences (
    user_id,
    display_name
  )
  values (
    new.id,
    new.name
  )
  on conflict (user_id) do nothing;

  return new;
end;
$$;


drop trigger if exists on_user_created_preferences on public.users;

create trigger on_user_created_preferences
  after insert on public.users
  for each row
  execute function public.create_user_preferences();


-- ---------------------------------------------------------------------------
-- Create preferences for existing users
-- ---------------------------------------------------------------------------
-- This makes sure users who already exist get a preferences row.
-- ---------------------------------------------------------------------------

insert into public.user_preferences (
  user_id,
  display_name
)
select
  id,
  name
from public.users
on conflict (user_id) do nothing;


-- ---------------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------------

alter table public.user_preferences enable row level security;
alter table public.hidden_users enable row level security;


-- ===========================================================================
-- USER PREFERENCES POLICIES
-- ===========================================================================

-- Users can see their own preferences.

create policy "Users can view their own preferences"
  on public.user_preferences
  for select
  using (
    auth.uid() = user_id
  );


-- Users can create their own preferences.

create policy "Users can insert their own preferences"
  on public.user_preferences
  for insert
  with check (
    auth.uid() = user_id
  );


-- Users can update their own preferences.

create policy "Users can update their own preferences"
  on public.user_preferences
  for update
  using (
    auth.uid() = user_id
  )
  with check (
    auth.uid() = user_id
  );


-- Users can delete their own preferences if ever required.

create policy "Users can delete their own preferences"
  on public.user_preferences
  for delete
  using (
    auth.uid() = user_id
  );


-- ===========================================================================
-- HIDDEN USERS POLICIES
-- ===========================================================================

-- A user can see the people they have hidden.

create policy "Users can view their hidden users"
  on public.hidden_users
  for select
  using (
    auth.uid() = user_id
  );


-- A user can hide another person.

create policy "Users can hide family members"
  on public.hidden_users
  for insert
  with check (
    auth.uid() = user_id
  );


-- A user can remove someone from their hidden list.

create policy "Users can unhide family members"
  on public.hidden_users
  for delete
  using (
    auth.uid() = user_id
  );
