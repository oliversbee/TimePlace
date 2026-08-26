# TimePlace — Supabase Database Schema

> Generated from the database schema information provided from the current Supabase project.
> This document describes the `public` schema only.

## Tables

### `public.users`

| Column | Type | Nullable | Default |
|---|---|---|---|
| `id` | uuid | NO | — |
| `name` | text | YES | — |
| `created_at` | timestamp with time zone | NO | `now()` |

### `public.user_preferences`

| Column | Type | Nullable | Default |
|---|---|---|---|
| `user_id` | uuid | NO | — |
| `display_name` | text | YES | — |
| `image_interval_seconds` | integer | NO | `300` |
| `show_own_image` | boolean | NO | `true` |
| `created_at` | timestamp with time zone | NO | `now()` |
| `updated_at` | timestamp with time zone | NO | `now()` |

### `public.households`

| Column | Type | Nullable | Default |
|---|---|---|---|
| `id` | uuid | NO | `gen_random_uuid()` |
| `name` | text | NO | — |
| `join_code` | text | NO | `upper(SUBSTRING(md5((random())::text) FROM 1 FOR 6))` |
| `created_by` | uuid | YES | — |
| `created_at` | timestamp with time zone | NO | `now()` |

### `public.household_members`

| Column | Type | Nullable | Default |
|---|---|---|---|
| `household_id` | uuid | NO | — |
| `user_id` | uuid | NO | — |
| `role` | text | NO | `'member'::text` |
| `joined_at` | timestamp with time zone | NO | `now()` |

### `public.images`

| Column | Type | Nullable | Default |
|---|---|---|---|
| `id` | uuid | NO | `gen_random_uuid()` |
| `user_id` | uuid | NO | — |
| `image_path` | text | NO | — |
| `taken_at` | timestamp with time zone | NO | `now()` |

### `public.hidden_users`

| Column | Type | Nullable | Default |
|---|---|---|---|
| `user_id` | uuid | NO | — |
| `hidden_user_id` | uuid | NO | — |
| `created_at` | timestamp with time zone | NO | `now()` |

### `public.nicknames`

| Column | Type | Nullable | Default |
|---|---|---|---|
| `viewer_id` | uuid | NO | — |
| `target_id` | uuid | NO | — |
| `nickname` | text | NO | — |
| `created_at` | timestamp with time zone | NO | `now()` |
| `updated_at` | timestamp with time zone | NO | `now()` |

### `public.device_claims`

| Column | Type | Nullable | Default |
|---|---|---|---|
| `device_id` | text | NO | — |
| `claim_code` | text | NO | — |
| `assigned_user_id` | uuid | YES | — |
| `created_at` | timestamp with time zone | NO | `now()` |
| `expires_at` | timestamp with time zone | NO | `(now() + '00:15:00'::interval)` |

---

# RLS

RLS is enabled on all eight public tables.

| Table | RLS Enabled | RLS Forced |
|---|---:|---:|
| `device_claims` | Yes | No |
| `hidden_users` | Yes | No |
| `household_members` | Yes | No |
| `households` | Yes | No |
| `images` | Yes | No |
| `nicknames` | Yes | No |
| `user_preferences` | Yes | No |
| `users` | Yes | No |

## RLS Policies

### `device_claims`

**Authenticated users can claim devices**
- Command: `UPDATE`
- Roles: `public`
- USING: `auth.role() = 'authenticated'`
- WITH CHECK: `assigned_user_id = auth.uid()`

**Public device claims lookup**
- Command: `SELECT`
- Roles: `public`
- USING: `true`

### `hidden_users`

**Users can hide family members**
- Command: `INSERT`
- Roles: `public`
- WITH CHECK: `auth.uid() = user_id`

**Users can unhide family members**
- Command: `DELETE`
- Roles: `public`
- USING: `auth.uid() = user_id`

**Users can view their hidden users**
- Command: `SELECT`
- Roles: `public`
- USING: `auth.uid() = user_id`

### `household_members`

**Members can view fellow household members**
- Command: `SELECT`
- Roles: `authenticated`
- USING: `is_household_member(household_id)`

**Users can insert themselves into households**
- Command: `INSERT`
- Roles: `authenticated`
- WITH CHECK: `user_id = auth.uid()`

**Users can leave households**
- Command: `DELETE`
- Roles: `authenticated`
- USING: `user_id = auth.uid()`

### `households`

**Members can view their households**
- Command: `SELECT`
- Roles: `authenticated`
- USING: `is_household_member(id)`

### `images`

**Users can insert their own images**
- Command: `INSERT`
- Roles: `authenticated`
- WITH CHECK: `auth.uid() = user_id`

**Users can view household images**
- Command: `SELECT`
- Roles: `authenticated`
- USING:
  `auth.uid() = user_id OR user_shares_household(user_id)`

### `nicknames`

**Users can remove their own nicknames**
- Command: `DELETE`
- Roles: `public`
- USING: `auth.uid() = viewer_id`

**Users can set their own nicknames**
- Command: `INSERT`
- Roles: `public`
- WITH CHECK: `auth.uid() = viewer_id`

**Users can update their own nicknames**
- Command: `UPDATE`
- Roles: `public`
- USING: `auth.uid() = viewer_id`
- WITH CHECK: `auth.uid() = viewer_id`

**Users can view their own nicknames**
- Command: `SELECT`
- Roles: `public`
- USING: `auth.uid() = viewer_id`

### `user_preferences`

**Users can delete their own preferences**
- Command: `DELETE`
- Roles: `public`
- USING: `auth.uid() = user_id`

**Users can insert their own preferences**
- Command: `INSERT`
- Roles: `public`
- WITH CHECK: `auth.uid() = user_id`

**Users can update their own preferences**
- Command: `UPDATE`
- Roles: `public`
- USING: `auth.uid() = user_id`
- WITH CHECK: `auth.uid() = user_id`

**Users can view their own preferences**
- Command: `SELECT`
- Roles: `public`
- USING: `auth.uid() = user_id`

### `users`

**Users can view all users**
- Command: `SELECT`
- Roles: `public`
- USING: `true`

---

# Functions

## `public.create_household(p_name text)`

- Returns: `households`
- Language: PL/pgSQL
- Security: `SECURITY DEFINER`
- Search path: `public`

```sql
CREATE OR REPLACE FUNCTION public.create_household(p_name text)
 RETURNS households
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_household public.households;
BEGIN

    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Not authenticated.';
    END IF;

    INSERT INTO public.households (
        name,
        created_by
    )
    VALUES (
        p_name,
        auth.uid()
    )
    RETURNING *
    INTO v_household;

    INSERT INTO public.household_members (
        household_id,
        user_id
    )
    VALUES (
        v_household.id,
        auth.uid()
    );

    RETURN v_household;
END;
$function$
```

## `public.create_user_preferences()`

- Returns: `trigger`
- Language: PL/pgSQL
- Security: `SECURITY DEFINER`
- Search path: `public`

```sql
CREATE OR REPLACE FUNCTION public.create_user_preferences()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$
```

## `public.get_latest_household_images()`

- Returns: `TABLE(id uuid, user_id uuid, image_path text, taken_at timestamp with time zone)`
- Language: SQL
- Volatility: `STABLE`
- Search path: `public`

```sql
CREATE OR REPLACE FUNCTION public.get_latest_household_images()
 RETURNS TABLE(id uuid, user_id uuid, image_path text, taken_at timestamp with time zone)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
    SELECT DISTINCT ON (i.user_id)
        i.id,
        i.user_id,
        i.image_path,
        i.taken_at
    FROM public.images i
    WHERE
        i.user_id = auth.uid()
        OR public.user_shares_household(i.user_id)
    ORDER BY
        i.user_id,
        i.taken_at DESC;
$function$
```

## `public.handle_new_auth_user()`

- Returns: `trigger`
- Language: PL/pgSQL
- Security: `SECURITY DEFINER`
- Search path: `public`

```sql
CREATE OR REPLACE FUNCTION public.handle_new_auth_user()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  insert into public.users (id, name)
  values (new.id, new.email)
  on conflict (id) do nothing;
  return new;
end;
$function$
```

## `public.is_household_member(p_household_id uuid)`

- Returns: `boolean`
- Language: SQL
- Security: `SECURITY DEFINER`
- Search path: `public`

```sql
CREATE OR REPLACE FUNCTION public.is_household_member(p_household_id uuid)
 RETURNS boolean
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
    SELECT EXISTS (
        SELECT 1
        FROM public.household_members hm
        WHERE hm.household_id = p_household_id
          AND hm.user_id = auth.uid()
    );
$function$
```

## `public.join_household(p_join_code text)`

- Returns: `uuid`
- Language: PL/pgSQL
- Security: `SECURITY DEFINER`
- Search path: `public`

```sql
CREATE OR REPLACE FUNCTION public.join_household(p_join_code text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_household_id uuid;
begin
  select id into v_household_id
  from public.households
  where join_code = upper(trim(p_join_code));

  if v_household_id is null then
    raise exception 'Invalid join code.';
  end if;

  insert into public.household_members (household_id, user_id)
  values (v_household_id, auth.uid())
  on conflict (household_id, user_id) do nothing;

  return v_household_id;
end;
$function$
```

## `public.leave_household(p_household_id uuid)`

- Returns: `boolean`
- Language: PL/pgSQL
- Security: `SECURITY DEFINER`
- Search path: `public`

```sql
CREATE OR REPLACE FUNCTION public.leave_household(p_household_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$

DECLARE
    remaining_members integer;
BEGIN

    IF NOT EXISTS (
        SELECT 1
        FROM public.household_members
        WHERE household_id = p_household_id
          AND user_id = auth.uid()
    ) THEN
        RAISE EXCEPTION 'You are not a member of this household';
    END IF;

    PERFORM pg_advisory_xact_lock(
        hashtext(p_household_id::text)
    );

    DELETE FROM public.household_members
    WHERE household_id = p_household_id
      AND user_id = auth.uid();

    SELECT COUNT(*)
    INTO remaining_members
    FROM public.household_members
    WHERE household_id = p_household_id;

    IF remaining_members = 0 THEN
        DELETE FROM public.households
        WHERE id = p_household_id;
    END IF;

    RETURN true;

END;

$function$
```

## `public.user_shares_household(target_user_id uuid)`

- Returns: `boolean`
- Language: SQL
- Volatility: `STABLE`
- Security: `SECURITY DEFINER`
- Search path: `public`

```sql
CREATE OR REPLACE FUNCTION public.user_shares_household(target_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
    SELECT EXISTS (
        SELECT 1
        FROM public.household_members viewer_membership
        JOIN public.household_members target_members
            ON target_members.household_id =
               viewer_membership.household_id
        WHERE viewer_membership.user_id = auth.uid()
          AND target_members.user_id = target_user_id
    );
$function$
```

---

# Triggers

## `users`

### `on_user_created_preferences`

- Event: `INSERT`
- Timing: `AFTER`
- Action:

```sql
EXECUTE FUNCTION create_user_preferences()
```

---

# Application Data Flow

```text
Supabase Auth
     │
     │ new user
     ▼
handle_new_auth_user()
     │
     ▼
public.users
     │
     └──► create_user_preferences()
                │
                ▼
        public.user_preferences


public.users
     │
     ├──────────────► public.images
     │
     ├──────────────► public.household_members
     │                         │
     │                         ▼
     │                   public.households
     │
     ├──────────────► public.hidden_users
     │
     └──────────────► public.nicknames


Device
  │
  ▼
device_claims
```

# Important Current Schema Details

- The image path column is **`images.image_path`**, not `image_url`.
- All public application tables currently have RLS enabled.
- Household creation is performed through `create_household(p_name)`.
- Household joining is performed through `join_household(p_join_code)`.
- Leaving a household is performed through `leave_household(p_household_id)`.
- Household membership checks are performed through `is_household_member(p_household_id)`.
- Whether two users share a household is determined by `user_shares_household(target_user_id)`.
- Latest household images are returned by `get_latest_household_images()`.
- A new user's `user_preferences` row is created by the `on_user_created_preferences` trigger.
- A new Auth user is inserted into `public.users` by `handle_new_auth_user()`.

# Notes / Limitations

This document is based on the schema output supplied from the current Supabase project.

The supplied schema output did **not** include a reliable complete index listing, so indexes are not documented here.

The supplied constraint query output was not included in the final schema data, so primary-key/foreign-key constraint definitions are not reproduced here beyond relationships that are evident from the supplied schema and application structure.
