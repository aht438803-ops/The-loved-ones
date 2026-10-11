-- إعداد المشاركة بين حسابك وحساب رحمة
-- استبدل البريدين بعنواني الحسابين المستخدمين في Supabase Auth ثم شغّل الملف في SQL Editor.
create extension if not exists pgcrypto;

-- Fail early with a clear message if the two Auth accounts are not configured yet.
do $$
declare boda_email text := 'boda812114@example.com'; rahma_email text := 'rahma812114@example.com';
begin
  if position('YOUR_EMAIL' in boda_email) > 0 or position('RAHMA_EMAIL' in rahma_email) > 0 then
    raise exception 'Replace both email placeholders in this SQL file before running it.';
  end if;
  if not exists(select 1 from auth.users where lower(email)=lower(boda_email)) then
    raise exception 'Boda email was not found in Supabase Auth. Create the user or correct the email.';
  end if;
  if not exists(select 1 from auth.users where lower(email)=lower(rahma_email)) then
    raise exception 'Rahma email was not found in Supabase Auth. Create the user or correct the email.';
  end if;
  if lower(boda_email) = lower(rahma_email) then
    raise exception 'Use two different Supabase Auth accounts for Boda and Rahma.';
  end if;
end $$;

create table if not exists public.couple_members (
  user_id uuid primary key references auth.users(id) on delete cascade,
  person text not null unique check (person in ('boda','rahma'))
);

insert into public.couple_members(user_id,person)
select id,'boda' from auth.users where lower(email)=lower('boda812114@example.com')
on conflict (user_id) do update set person=excluded.person;
insert into public.couple_members(user_id,person)
select id,'rahma' from auth.users where lower(email)=lower('rahma812114@example.com')
on conflict (user_id) do update set person=excluded.person;

create table if not exists public.love_letters (
  user_id uuid primary key references auth.users(id) on delete cascade,
  person text not null unique check (person in ('boda','rahma')),
  body text not null default '',
  updated_at timestamptz not null default now()
);
alter table public.love_letters enable row level security;
drop policy if exists "members read love letters" on public.love_letters;
create policy "members read love letters" on public.love_letters for select to authenticated using (exists(select 1 from public.couple_members where user_id=auth.uid()));
drop policy if exists "members create own letter" on public.love_letters;
create policy "members create own letter" on public.love_letters for insert to authenticated with check (user_id=auth.uid() and exists(select 1 from public.couple_members m where m.user_id=auth.uid() and m.person=love_letters.person));
drop policy if exists "members update own letter" on public.love_letters;
create policy "members update own letter" on public.love_letters for update to authenticated using (user_id=auth.uid()) with check (user_id=auth.uid() and exists(select 1 from public.couple_members m where m.user_id=auth.uid() and m.person=love_letters.person));

insert into public.love_letters(user_id,person,body)
select user_id,'boda','رحمه حبيبتي 😍، إنتي رحمة لقلبي وحياتي 💕 وجودك جنبي بيخليني مطمّن مهما الدنيا اتقلبت 🌹 وضحكتك هي السبب اللي بيخليني أحب كل يوم جديد 💖.'
from public.couple_members where person='boda'
on conflict (user_id) do nothing;

grant select,insert,update on public.love_letters to authenticated;
grant select on public.couple_members to authenticated;
alter table public.couple_members enable row level security;
drop policy if exists "members read own membership" on public.couple_members;
create policy "members read own membership" on public.couple_members for select to authenticated using (user_id=auth.uid());

create table if not exists public.shared_songs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  path text not null unique,
  mime_type text,
  created_at timestamptz not null default now()
);
alter table public.shared_songs enable row level security;
drop policy if exists "members read shared songs" on public.shared_songs;
create policy "members read shared songs" on public.shared_songs for select to authenticated using (exists(select 1 from public.couple_members where user_id=auth.uid()));
drop policy if exists "members add own songs" on public.shared_songs;
create policy "members add own songs" on public.shared_songs for insert to authenticated with check (user_id=auth.uid() and exists(select 1 from public.couple_members where user_id=auth.uid()));
drop policy if exists "members delete own songs" on public.shared_songs;
create policy "members delete own songs" on public.shared_songs for delete to authenticated using (user_id=auth.uid());
grant select,insert,delete on public.shared_songs to authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('rahma-songs','rahma-songs',false,52428800,array['audio/*'])
on conflict (id) do update set public=false,file_size_limit=52428800,allowed_mime_types=array['audio/*'];
drop policy if exists "members read shared audio" on storage.objects;
create policy "members read shared audio" on storage.objects for select to authenticated using (bucket_id='rahma-songs' and exists(select 1 from public.couple_members where user_id=auth.uid()));
drop policy if exists "members upload own audio" on storage.objects;
create policy "members upload own audio" on storage.objects for insert to authenticated with check (bucket_id='rahma-songs' and (storage.foldername(name))[1]=auth.uid()::text and exists(select 1 from public.couple_members where user_id=auth.uid()));
drop policy if exists "members delete own audio" on storage.objects;
create policy "members delete own audio" on storage.objects for delete to authenticated using (bucket_id='rahma-songs' and (storage.foldername(name))[1]=auth.uid()::text);

-- Enable live updates for shared songs and letters, if not already enabled.
do $$ begin
  if exists(select 1 from pg_publication where pubname='supabase_realtime') then
    if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='shared_songs') then alter publication supabase_realtime add table public.shared_songs; end if;
    if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='love_letters') then alter publication supabase_realtime add table public.love_letters; end if;
  end if;
end $$;


-- Presence is private: only the two registered couple accounts can see each other online.
drop policy if exists "couple can read private presence" on realtime.messages;
create policy "couple can read private presence" on realtime.messages
for select to authenticated
using (
  realtime.topic() = 'rahma-couple-presence'
  and realtime.messages.extension = 'presence'
  and exists (select 1 from public.couple_members where user_id = auth.uid())
);
drop policy if exists "couple can publish private presence" on realtime.messages;
create policy "couple can publish private presence" on realtime.messages
for insert to authenticated
with check (
  realtime.topic() = 'rahma-couple-presence'
  and realtime.messages.extension = 'presence'
  and exists (select 1 from public.couple_members where user_id = auth.uid())
);

-- Add author ids so the app can avoid notifying the person who made the change.
alter table if exists public.chat_messages add column if not exists user_id uuid references auth.users(id) on delete set null;
alter table if exists public.memories add column if not exists user_id uuid references auth.users(id) on delete set null;

-- Add existing chat and memory tables to Realtime when present.
do $$ begin
  if exists(select 1 from pg_publication where pubname='supabase_realtime') then
    if to_regclass('public.chat_messages') is not null and not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='chat_messages') then alter publication supabase_realtime add table public.chat_messages; end if;
    if to_regclass('public.memories') is not null and not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='memories') then alter publication supabase_realtime add table public.memories; end if;
  end if;
end $$;
