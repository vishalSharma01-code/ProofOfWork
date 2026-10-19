-- ProofOfWork schema for Supabase
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default '',
  username text unique,
  bio text not null default '',
  skills text[] not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.portfolio_entries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  title text not null,
  description text not null default '',
  evidence_url text,
  entry_type text not null default 'Project' check (entry_type in ('Project','Certificate','Hackathon')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists portfolio_entries_user_id_idx on public.portfolio_entries(user_id);

create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end;
$$;

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at before update on public.profiles
for each row execute function public.set_updated_at();

drop trigger if exists entries_set_updated_at on public.portfolio_entries;
create trigger entries_set_updated_at before update on public.portfolio_entries
for each row execute function public.set_updated_at();

-- Create a profile automatically whenever a new auth user signs up.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  proposed_username text;
begin
  proposed_username := lower(regexp_replace(coalesce(new.raw_user_meta_data->>'username', split_part(coalesce(new.email, 'student'), '@', 1)), '[^a-zA-Z0-9_-]', '', 'g'));
  if proposed_username = '' then proposed_username := 'student'; end if;
  proposed_username := left(proposed_username, 35) || '-' || left(replace(new.id::text, '-', ''), 6);

  insert into public.profiles (id, display_name, username)
  values (
    new.id,
    coalesce(nullif(new.raw_user_meta_data->>'display_name',''), split_part(coalesce(new.email, ''), '@', 1), 'Student'),
    proposed_username
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute procedure public.handle_new_user();

alter table public.profiles enable row level security;
alter table public.portfolio_entries enable row level security;

drop policy if exists "Profiles are publicly readable" on public.profiles;
create policy "Profiles are publicly readable" on public.profiles
for select using (true);

drop policy if exists "Users insert their own profile" on public.profiles;
create policy "Users insert their own profile" on public.profiles
for insert with check (auth.uid() = id);

drop policy if exists "Users update their own profile" on public.profiles;
create policy "Users update their own profile" on public.profiles
for update using (auth.uid() = id) with check (auth.uid() = id);

drop policy if exists "Entries are publicly readable" on public.portfolio_entries;
create policy "Entries are publicly readable" on public.portfolio_entries
for select using (true);

drop policy if exists "Users create their own entries" on public.portfolio_entries;
create policy "Users create their own entries" on public.portfolio_entries
for insert with check (auth.uid() = user_id);

drop policy if exists "Users update their own entries" on public.portfolio_entries;
create policy "Users update their own entries" on public.portfolio_entries
for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "Users delete their own entries" on public.portfolio_entries;
create policy "Users delete their own entries" on public.portfolio_entries
for delete using (auth.uid() = user_id);

grant usage on schema public to anon, authenticated;
grant select on public.profiles, public.portfolio_entries to anon, authenticated;
grant insert, update on public.profiles to authenticated;
grant insert, update, delete on public.portfolio_entries to authenticated;
