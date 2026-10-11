-- إعداد المشاركة بين حسابك وحساب رحمة
-- استبدل البريدين بعنواني الحسابين المستخدمين في Supabase Auth ثم شغّل الملف في SQL Editor.
create extension if not exists pgcrypto;

create table if not exists public.couple_members (
  user_id uuid primary key references auth.users(id) on delete cascade,
  person text not null unique check (person in ('boda','rahma'))
);

insert into public.couple_members(user_id,person)
select id,'boda' from auth.users where lower(email)=lower('YOUR_EMAIL@example.com')
on conflict (user_id) do update set person=excluded.person;
insert into public.couple_members(user_id,person)
select id,'rahma' from auth.users where lower(email)=lower('RAHMA_EMAIL@example.com')
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
on conflict (id) do update set public=false,file_size_limit=52428800;
drop policy if exists "members read shared audio" on storage.objects;
create policy "members read shared audio" on storage.objects for select to authenticated using (bucket_id='rahma-songs' and exists(select 1 from public.couple_members where user_id=auth.uid()));
drop policy if exists "members upload own audio" on storage.objects;
create policy "members upload own audio" on storage.objects for insert to authenticated with check (bucket_id='rahma-songs' and (storage.foldername(name))[1]=auth.uid()::text and exists(select 1 from public.couple_members where user_id=auth.uid()));
drop policy if exists "members delete own audio" on storage.objects;
create policy "members delete own audio" on storage.objects for delete to authenticated using (bucket_id='rahma-songs' and (storage.foldername(name))[1]=auth.uid()::text);

-- Enable live updates for shared songs and letters, if not already enabled.
do $$ begin
  if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='shared_songs') then alter publication supabase_realtime add table public.shared_songs; end if;
  if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='love_letters') then alter publication supabase_realtime add table public.love_letters; end if;
end $$;

