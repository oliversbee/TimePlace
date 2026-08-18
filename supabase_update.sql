-- ============================================================================
-- MIGRATION: MULTI-HOUSEHOLD, DEVICE PAIRING & SHARED VISIBILITY
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. HOUSEHOLDS & MEMBERSHIP
-- ---------------------------------------------------------------------------

-- Store explicit household entities with auto-generated secure join codes.
create table if not exists public.households (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  join_code text unique not null default upper(substring(md5(random()::text) from 1 for 6)),
  created_by uuid references public.users(id) on delete set null,
  created_at timestamptz not null default now()
);

-- Junction table allowing users to belong to N households.
create table if not exists public.household_members (
  household_id uuid not null references public.households(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  role text not null default 'member',
  joined_at timestamptz not null default now(),

  primary key (household_id, user_id)
);

create index if not exists household_members_user_idx
  on public.household_members(user_id);

-- ---------------------------------------------------------------------------
-- 2. DEVICE PAIRING (Plug-and-Play E-Paper Displays)
-- ---------------------------------------------------------------------------

-- Handles TV-style 6-digit claim codes for hardware displays.
create table if not exists public.device_claims (
  device_id text primary key,
  claim_code text not null unique,
  assigned_user_id uuid references public.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '15 minutes')
);

-- ---------------------------------------------------------------------------
-- 3. MIGRATE OLD FLAT HOUSEHOLD TABLE
-- ---------------------------------------------------------------------------

-- Create a default household for existing users if any exist.
do $$
declare
  default_household_id uuid;
begin
  if exists (select 1 from public.users) then
    insert into public.households (name)
    values ('My Household')
    returning id into default_household_id;

    insert into public.household_members (household_id, user_id, role)
    select default_household_id, id, 'owner'
    from public.users
    on conflict do nothing;
  end if;
end $$;

-- Drop legacy flat household summary table
drop table if exists public.household;

-- ---------------------------------------------------------------------------
-- 4. JOIN HOUSEHOLD RPC FUNCTION
-- ---------------------------------------------------------------------------

-- Secure function allowing users to join a household using a 6-character code
create or replace function public.join_household(p_join_code text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_household_id uuid;
begin
  -- Search for household matching code
  select id into v_household_id
  from public.households
  where join_code = upper(trim(p_join_code));

  if v_household_id is null then
    raise exception 'Invalid join code.';
  end if;

  -- Insert user into household_members
  insert into public.household_members (household_id, user_id)
  values (v_household_id, auth.uid())
  on conflict (household_id, user_id) do nothing;

  return v_household_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. ROW LEVEL SECURITY (RLS) POLICIES
-- ---------------------------------------------------------------------------

alter table public.households enable row level security;
alter table public.household_members enable row level security;
alter table public.device_claims enable row level security;

-- Households Policies
create policy "Members can view their households"
  on public.households for select
  using (
    id in (
      select household_id from public.household_members where user_id = auth.uid()
    )
  );

create policy "Users can create households"
  on public.households for insert
  with check (auth.role() = 'authenticated');

-- Household Members Policies
create policy "Members can view fellow household members"
  on public.household_members for select
  using (
    household_id in (
      select household_id from public.household_members where user_id = auth.uid()
    )
  );

create policy "Users can insert themselves into households"
  on public.household_members for insert
  with check (user_id = auth.uid());

-- Device Claims Policies
create policy "Authenticated users can claim devices"
  on public.device_claims for update
  using (auth.role() = 'authenticated')
  with check (assigned_user_id = auth.uid());

create policy "Public device claims lookup"
  on public.device_claims for select
  using (true);
