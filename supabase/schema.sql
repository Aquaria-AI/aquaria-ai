-- Aquaria Supabase Schema
-- Run this in the Supabase SQL Editor to set up your database.

-- ============================================================
-- TABLES
-- ============================================================

-- Profiles (extends Supabase auth.users)
create table if not exists public.profiles (
  id uuid references auth.users(id) on delete cascade primary key,
  display_name text,
  username text unique,
  closed_at timestamptz,             -- non-null = account closed (soft-delete)
  created_at timestamptz default now() not null,
  updated_at timestamptz default now() not null
);

-- Check username availability (bypasses RLS for cross-user lookup)
create or replace function public.is_username_available(desired_username text)
returns boolean as $$
begin
  return not exists (
    select 1 from public.profiles where username = lower(desired_username)
  );
end;
$$ language plpgsql security definer;

-- Tanks
create table if not exists public.tanks (
  id text primary key,
  user_id uuid references auth.users(id) on delete cascade not null,
  name text not null,
  gallons int not null default 0,
  water_type text not null default 'freshwater',
  is_archived boolean not null default false,
  archived_at timestamptz,
  tap_water_json text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Inhabitants
create table if not exists public.inhabitants (
  id bigint generated always as identity primary key,
  tank_id text references public.tanks(id) on delete cascade not null,
  user_id uuid references auth.users(id) on delete cascade not null,
  name text not null,
  count int not null default 1,
  type text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Plants
create table if not exists public.plants (
  id bigint generated always as identity primary key,
  tank_id text references public.tanks(id) on delete cascade not null,
  user_id uuid references auth.users(id) on delete cascade not null,
  name text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Logs
create table if not exists public.logs (
  id bigint generated always as identity primary key,
  tank_id text references public.tanks(id) on delete cascade not null,
  user_id uuid references auth.users(id) on delete cascade not null,
  raw_text text not null default '',
  parsed_json text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Tasks (reminders + alerts)
create table if not exists public.tasks (
  id bigint generated always as identity primary key,
  tank_id text references public.tanks(id) on delete cascade not null,
  user_id uuid references auth.users(id) on delete cascade not null,
  description text not null,
  due_date date,
  priority text not null default 'normal',
  source text not null default 'ai',
  is_dismissed boolean not null default false,
  dismissed_at timestamptz,
  repeat_days int,
  is_paused boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Dismissed tasks (legacy, kept for migration)
create table if not exists public.dismissed_tasks (
  task_key text not null,
  user_id uuid references auth.users(id) on delete cascade not null,
  created_at timestamptz not null default now(),
  primary key (user_id, task_key)
);

-- ============================================================
-- INDEXES
-- ============================================================

create index if not exists idx_tanks_user_id on public.tanks(user_id);
create index if not exists idx_inhabitants_tank_id on public.inhabitants(tank_id);
create index if not exists idx_inhabitants_user_id on public.inhabitants(user_id);
create index if not exists idx_plants_tank_id on public.plants(tank_id);
create index if not exists idx_plants_user_id on public.plants(user_id);
create index if not exists idx_logs_tank_id on public.logs(tank_id);
create index if not exists idx_logs_user_id on public.logs(user_id);
create index if not exists idx_logs_created_at on public.logs(created_at desc);
create index if not exists idx_tasks_tank_id on public.tasks(tank_id);
create index if not exists idx_tasks_user_id on public.tasks(user_id);
create index if not exists idx_tasks_due_date on public.tasks(due_date);

-- ============================================================
-- AUTO-UPDATE updated_at TRIGGER
-- ============================================================

create or replace function public.set_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

create or replace trigger trg_tanks_updated_at
  before update on public.tanks
  for each row execute function public.set_updated_at();

create or replace trigger trg_inhabitants_updated_at
  before update on public.inhabitants
  for each row execute function public.set_updated_at();

create or replace trigger trg_plants_updated_at
  before update on public.plants
  for each row execute function public.set_updated_at();

create or replace trigger trg_logs_updated_at
  before update on public.logs
  for each row execute function public.set_updated_at();

create or replace trigger trg_tasks_updated_at
  before update on public.tasks
  for each row execute function public.set_updated_at();

-- ============================================================
-- AUTO-CREATE PROFILE ON SIGNUP
-- ============================================================

create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, new.raw_user_meta_data->>'full_name');
  return new;
end;
$$ language plpgsql security definer;

create or replace trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ============================================================
-- ROW LEVEL SECURITY (RLS)
-- ============================================================

alter table public.profiles enable row level security;
alter table public.tanks enable row level security;
alter table public.inhabitants enable row level security;
alter table public.plants enable row level security;
alter table public.logs enable row level security;
alter table public.tasks enable row level security;
alter table public.dismissed_tasks enable row level security;

-- Helper: returns true if the calling user's account is open (not closed).
create or replace function public.account_is_open()
returns boolean as $$
begin
  return not exists (
    select 1 from public.profiles
    where id = auth.uid() and closed_at is not null
  );
end;
$$ language plpgsql security definer stable;

-- Profiles: users can read own profile (even if closed, so app can detect it),
-- but can only update if account is open.
create policy "Users can view own profile"
  on public.profiles for select using (auth.uid() = id);
create policy "Users can update own profile"
  on public.profiles for update using (auth.uid() = id and closed_at is null);

-- Tanks: users can CRUD their own tanks (blocked if account closed)
create policy "Users can view own tanks"
  on public.tanks for select using (auth.uid() = user_id and public.account_is_open());
create policy "Users can insert own tanks"
  on public.tanks for insert with check (auth.uid() = user_id and public.account_is_open());
create policy "Users can update own tanks"
  on public.tanks for update using (auth.uid() = user_id and public.account_is_open());
create policy "Users can delete own tanks"
  on public.tanks for delete using (auth.uid() = user_id and public.account_is_open());

-- Inhabitants
create policy "Users can view own inhabitants"
  on public.inhabitants for select using (auth.uid() = user_id and public.account_is_open());
create policy "Users can insert own inhabitants"
  on public.inhabitants for insert with check (auth.uid() = user_id and public.account_is_open());
create policy "Users can update own inhabitants"
  on public.inhabitants for update using (auth.uid() = user_id and public.account_is_open());
create policy "Users can delete own inhabitants"
  on public.inhabitants for delete using (auth.uid() = user_id and public.account_is_open());

-- Plants
create policy "Users can view own plants"
  on public.plants for select using (auth.uid() = user_id and public.account_is_open());
create policy "Users can insert own plants"
  on public.plants for insert with check (auth.uid() = user_id and public.account_is_open());
create policy "Users can update own plants"
  on public.plants for update using (auth.uid() = user_id and public.account_is_open());
create policy "Users can delete own plants"
  on public.plants for delete using (auth.uid() = user_id and public.account_is_open());

-- Logs
create policy "Users can view own logs"
  on public.logs for select using (auth.uid() = user_id and public.account_is_open());
create policy "Users can insert own logs"
  on public.logs for insert with check (auth.uid() = user_id and public.account_is_open());
create policy "Users can update own logs"
  on public.logs for update using (auth.uid() = user_id and public.account_is_open());
create policy "Users can delete own logs"
  on public.logs for delete using (auth.uid() = user_id and public.account_is_open());

-- Tasks
create policy "Users can view own tasks"
  on public.tasks for select using (auth.uid() = user_id and public.account_is_open());
create policy "Users can insert own tasks"
  on public.tasks for insert with check (auth.uid() = user_id and public.account_is_open());
create policy "Users can update own tasks"
  on public.tasks for update using (auth.uid() = user_id and public.account_is_open());
create policy "Users can delete own tasks"
  on public.tasks for delete using (auth.uid() = user_id and public.account_is_open());

-- Dismissed tasks
create policy "Users can view own dismissed tasks"
  on public.dismissed_tasks for select using (auth.uid() = user_id and public.account_is_open());
create policy "Users can insert own dismissed tasks"
  on public.dismissed_tasks for insert with check (auth.uid() = user_id and public.account_is_open());
create policy "Users can delete own dismissed tasks"
  on public.dismissed_tasks for delete using (auth.uid() = user_id and public.account_is_open());

-- User notifications (moderation alerts, etc.)
create table if not exists public.user_notifications (
  id bigint generated always as identity primary key,
  user_id uuid references auth.users(id) on delete cascade not null,
  title text not null,
  message text not null,
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists idx_user_notifications_user_id on public.user_notifications(user_id);

alter table public.user_notifications enable row level security;

create policy "Users can view own notifications"
  on public.user_notifications for select using (auth.uid() = user_id);
create policy "Users can update own notifications"
  on public.user_notifications for update using (auth.uid() = user_id);
-- Admin can insert notifications for any user
create policy "Admin can insert notifications"
  on public.user_notifications for insert with check (
    auth.uid() = (select id from auth.users where email = 'admin@aquaria-ai.com' limit 1)
  );

-- ============================================================
-- MODERATION DASHBOARD VIEW (admin only)
-- ============================================================
-- Aggregates per-user moderation stats from community_posts,
-- post_flags, and user_notifications. Readable only by admin.

create or replace view public.moderation_users as
select
  u.id as user_id,
  u.email,
  p.display_name,
  p.username,
  p.created_at as account_created,
  coalesce(posts.total_posts, 0) as total_posts,
  coalesce(flagged.posts_flagged, 0) as posts_flagged,
  coalesce(hidden.posts_hidden, 0) as posts_hidden,
  coalesce(deleted.posts_deleted_by_admin, 0) as posts_deleted_by_admin,
  coalesce(flags_cast.flags_submitted, 0) as flags_submitted
from auth.users u
join public.profiles p on p.id = u.id
left join (
  select user_id, count(*) as total_posts
  from public.community_posts
  group by user_id
) posts on posts.user_id = u.id
left join (
  select cp.user_id, count(distinct cp.id) as posts_flagged
  from public.community_posts cp
  join public.post_flags pf on pf.post_id = cp.id
  group by cp.user_id
) flagged on flagged.user_id = u.id
left join (
  select user_id, count(*) as posts_hidden
  from public.community_posts
  where is_hidden = true
  group by user_id
) hidden on hidden.user_id = u.id
left join (
  select user_id, count(*) as posts_deleted_by_admin
  from public.user_notifications
  where title = 'Post removed'
  group by user_id
) deleted on deleted.user_id = u.id
left join (
  select user_id, count(*) as flags_submitted
  from public.post_flags
  group by user_id
) flags_cast on flags_cast.user_id = u.id;

-- Legal acceptances — records user acknowledgement of T&C and Privacy Policy
create table if not exists public.legal_acceptances (
  id bigint generated always as identity primary key,
  user_id uuid references auth.users(id) on delete cascade not null,
  email text,
  username text,
  terms_version text not null,
  privacy_version text not null,
  accepted_at timestamptz default now() not null,
  app_version text,
  device_info text
);

alter table public.legal_acceptances enable row level security;

create policy "Users can view own acceptances"
  on public.legal_acceptances for select using (auth.uid() = user_id);
create policy "Users can insert own acceptances"
  on public.legal_acceptances for insert with check (auth.uid() = user_id);

-- ============================================================
-- COMMUNITY (General Channel)
-- ============================================================

-- Posts: photo + caption shared to the general channel
create table if not exists public.community_posts (
  id bigint generated always as identity primary key,
  user_id uuid references auth.users(id) on delete cascade not null,
  channel text not null default 'general',
  photo_url text not null,
  caption text not null default '',
  is_hidden boolean not null default false,
  admin_action text,               -- null = no action, 'deleted' = removed by admin, 'restored' = cleared by admin
  admin_action_at timestamptz,
  created_at timestamptz not null default now(),
  -- Direct FK to profiles so PostgREST can resolve the join
  constraint community_posts_profile_fk foreign key (user_id) references public.profiles(id)
);

-- Flags: one flag per user per post
create table if not exists public.post_flags (
  id bigint generated always as identity primary key,
  post_id bigint references public.community_posts(id) on delete cascade not null,
  user_id uuid references auth.users(id) on delete cascade not null,
  reason text not null default 'inappropriate',
  created_at timestamptz not null default now(),
  unique(post_id, user_id)
);

create index if not exists idx_post_flags_post_id on public.post_flags(post_id);

alter table public.post_flags enable row level security;

-- All authenticated users can flag posts
create policy "Users can flag posts"
  on public.post_flags for insert with check (auth.uid() = user_id);
-- Users can see their own flags (to know they already flagged)
create policy "Users can view own flags"
  on public.post_flags for select using (auth.uid() = user_id);
-- Admin can see all flags
create policy "Admin can view all flags"
  on public.post_flags for select using (
    auth.uid() = (select id from auth.users where email = 'admin@aquaria-ai.com' limit 1)
  );

-- Auto-hide posts when flag count reaches 2 and notify admin
create or replace function public.check_flag_count()
returns trigger as $$
declare
  admin_uid uuid;
  post_author uuid;
  author_email text;
begin
  if (select count(*) from public.post_flags where post_id = new.post_id) >= 2 then
    -- Hide the post
    update public.community_posts set is_hidden = true where id = new.post_id;

    -- Notify admin
    select id into admin_uid from auth.users where email = 'admin@aquaria-ai.com' limit 1;
    select user_id into post_author from public.community_posts where id = new.post_id;
    select email into author_email from auth.users where id = post_author;

    if admin_uid is not null then
      insert into public.user_notifications (user_id, title, message)
      values (
        admin_uid,
        'Flagged post auto-hidden',
        'Post #' || new.post_id || ' by ' || coalesce(author_email, 'unknown') || ' has been flagged by multiple users and auto-hidden. Review it in the Flagged tab.'
      );
    end if;
  end if;
  return new;
end;
$$ language plpgsql security definer;

create or replace trigger trg_post_flag_check
  after insert on public.post_flags
  for each row execute function public.check_flag_count();

-- Reactions: positive emoji reactions on posts (one per user per emoji per post)
create table if not exists public.post_reactions (
  id bigint generated always as identity primary key,
  post_id bigint references public.community_posts(id) on delete cascade not null,
  user_id uuid references auth.users(id) on delete cascade not null,
  emoji text not null,
  created_at timestamptz not null default now(),
  unique(post_id, user_id, emoji)
);

create index if not exists idx_community_posts_created on public.community_posts(created_at desc);
create index if not exists idx_post_reactions_post_id on public.post_reactions(post_id);

alter table public.community_posts enable row level security;
alter table public.post_reactions enable row level security;

-- All authenticated users can view all posts (public channel)
create policy "Anyone can view posts"
  on public.community_posts for select using (auth.uid() is not null);
-- Users can create their own posts
create policy "Users can create own posts"
  on public.community_posts for insert with check (auth.uid() = user_id);
-- Users can delete their own posts
create policy "Users can delete own posts"
  on public.community_posts for delete using (auth.uid() = user_id);

-- All authenticated users can view all reactions
create policy "Anyone can view reactions"
  on public.post_reactions for select using (auth.uid() is not null);
-- Users can add their own reactions
create policy "Users can add own reactions"
  on public.post_reactions for insert with check (auth.uid() = user_id);
-- Users can remove their own reactions
create policy "Users can remove own reactions"
  on public.post_reactions for delete using (auth.uid() = user_id);

-- ============================================================
-- CLOSE USER ACCOUNT (soft-delete)
-- ============================================================
-- Marks the account as closed by setting profiles.closed_at.
-- Data is retained per privacy policy (up to 12 months) but is
-- inaccessible to the app because RLS policies exclude closed accounts.
-- Called from the app via: client.rpc('close_user_account')

create or replace function public.close_user_account()
returns void as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'Not authenticated';
  end if;

  -- Mark the profile as closed
  update public.profiles
    set closed_at = now(),
        updated_at = now()
    where id = uid;
end;
$$ language plpgsql security definer;

-- ============================================================
-- CLONE SAMPLE TANK FOR NEW USERS
-- ============================================================
-- Copies the "Sample Tank" from the sample-tank@aquaria-ai.com user
-- into the new user's account. Called once after signup.
-- Uses security definer to bypass RLS (reads from another user's data).

create or replace function public.clone_sample_tank(target_user_id uuid)
returns void as $$
declare
  sample_uid uuid;
  src_tank record;
  new_tank_id text;
  inh record;
  plt record;
  lg record;
begin
  -- Find the sample-tank user
  select id into sample_uid
    from auth.users
    where email = 'sample-tank@aquaria-ai.com'
    limit 1;
  if sample_uid is null then return; end if;

  -- Don't clone if the target user already has tanks
  if exists (select 1 from public.tanks where user_id = target_user_id limit 1) then
    return;
  end if;

  -- Find the "Sample Tank"
  select * into src_tank
    from public.tanks
    where user_id = sample_uid and name = 'Sample Tank' and is_archived = false
    limit 1;
  if src_tank is null then return; end if;

  -- Generate a new tank ID
  new_tank_id := gen_random_uuid()::text;

  -- Clone the tank
  insert into public.tanks (id, user_id, name, gallons, water_type, is_archived, tap_water_json, created_at)
  values (new_tank_id, target_user_id, src_tank.name, src_tank.gallons, src_tank.water_type, false, src_tank.tap_water_json, now());

  -- Clone inhabitants
  for inh in
    select name, count, type from public.inhabitants where tank_id = src_tank.id
  loop
    insert into public.inhabitants (tank_id, user_id, name, count, type)
    values (new_tank_id, target_user_id, inh.name, inh.count, inh.type);
  end loop;

  -- Clone plants
  for plt in
    select name from public.plants where tank_id = src_tank.id
  loop
    insert into public.plants (tank_id, user_id, name)
    values (new_tank_id, target_user_id, plt.name);
  end loop;

  -- Clone logs (keep original created_at for realistic history)
  for lg in
    select raw_text, parsed_json, created_at from public.logs where tank_id = src_tank.id
  loop
    insert into public.logs (tank_id, user_id, raw_text, parsed_json, created_at)
    values (new_tank_id, target_user_id, lg.raw_text, lg.parsed_json, lg.created_at);
  end loop;

  -- Clone tasks (recurring and one-time, only active ones)
  for lg in
    select description, due_date, priority, source, repeat_days, is_paused
    from public.tasks
    where tank_id = src_tank.id and is_dismissed = false
  loop
    insert into public.tasks (tank_id, user_id, description, due_date, priority, source, repeat_days, is_paused)
    values (new_tank_id, target_user_id, lg.description, lg.due_date, lg.priority, lg.source, lg.repeat_days, lg.is_paused);
  end loop;
end;
$$ language plpgsql security definer;
