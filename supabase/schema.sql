-- Aquaria Supabase Schema
-- Run this in the Supabase SQL Editor to set up your database.

-- ============================================================
-- TABLES
-- ============================================================

-- Profiles (extends Supabase auth.users)
create table if not exists public.profiles (
  id uuid references auth.users(id) on delete cascade primary key,
  display_name text,
  created_at timestamptz default now() not null,
  updated_at timestamptz default now() not null
);

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

-- Dismissed tasks
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

-- ============================================================
-- AUTO-CREATE PROFILE ON SIGNUP
-- ============================================================

create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data->>'full_name', new.email));
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
alter table public.dismissed_tasks enable row level security;

-- Profiles: users can only read/update their own profile
create policy "Users can view own profile"
  on public.profiles for select using (auth.uid() = id);
create policy "Users can update own profile"
  on public.profiles for update using (auth.uid() = id);

-- Tanks: users can CRUD their own tanks
create policy "Users can view own tanks"
  on public.tanks for select using (auth.uid() = user_id);
create policy "Users can insert own tanks"
  on public.tanks for insert with check (auth.uid() = user_id);
create policy "Users can update own tanks"
  on public.tanks for update using (auth.uid() = user_id);
create policy "Users can delete own tanks"
  on public.tanks for delete using (auth.uid() = user_id);

-- Inhabitants
create policy "Users can view own inhabitants"
  on public.inhabitants for select using (auth.uid() = user_id);
create policy "Users can insert own inhabitants"
  on public.inhabitants for insert with check (auth.uid() = user_id);
create policy "Users can update own inhabitants"
  on public.inhabitants for update using (auth.uid() = user_id);
create policy "Users can delete own inhabitants"
  on public.inhabitants for delete using (auth.uid() = user_id);

-- Plants
create policy "Users can view own plants"
  on public.plants for select using (auth.uid() = user_id);
create policy "Users can insert own plants"
  on public.plants for insert with check (auth.uid() = user_id);
create policy "Users can update own plants"
  on public.plants for update using (auth.uid() = user_id);
create policy "Users can delete own plants"
  on public.plants for delete using (auth.uid() = user_id);

-- Logs
create policy "Users can view own logs"
  on public.logs for select using (auth.uid() = user_id);
create policy "Users can insert own logs"
  on public.logs for insert with check (auth.uid() = user_id);
create policy "Users can update own logs"
  on public.logs for update using (auth.uid() = user_id);
create policy "Users can delete own logs"
  on public.logs for delete using (auth.uid() = user_id);

-- Dismissed tasks
create policy "Users can view own dismissed tasks"
  on public.dismissed_tasks for select using (auth.uid() = user_id);
create policy "Users can insert own dismissed tasks"
  on public.dismissed_tasks for insert with check (auth.uid() = user_id);
create policy "Users can delete own dismissed tasks"
  on public.dismissed_tasks for delete using (auth.uid() = user_id);
