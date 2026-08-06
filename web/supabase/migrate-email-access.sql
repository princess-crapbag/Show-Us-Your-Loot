-- Authorise by email instead of by user id.
--
-- The first design keyed access on auth.users.id, which meant a person had to
-- sign in before they could be granted anything — you could not invite an
-- officer ahead of time, and "signed in but no data" looked like a failure.
--
-- Access is now keyed on the email address in the signed-in token, so an
-- address can be authorised before that person has ever logged in. Their
-- first sign-in simply works.
--
-- Safe to run on an existing project. Existing members are carried across.

create table if not exists syl_allowed (
    guild_id   uuid not null references syl_guilds(id) on delete cascade,
    email      text not null,
    role       text not null default 'officer',
    added_at   timestamptz not null default now(),
    primary key (guild_id, email)
);

alter table syl_allowed enable row level security;

-- Carry over anyone already granted access under the old scheme.
insert into syl_allowed (guild_id, email)
select m.guild_id, lower(u.email)
from syl_members m
join auth.users u on u.id = m.user_id
where u.email is not null
on conflict do nothing;

-- Matching is case-insensitive: nobody should be locked out by capitalisation.
create or replace function syl_may_read(p_guild uuid)
returns boolean
language sql
stable
security definer
set search_path = public, extensions
as $$
    select exists (
        select 1
        from syl_allowed a
        where a.guild_id = p_guild
          and lower(a.email) = lower(coalesce(auth.jwt() ->> 'email', ''))
    );
$$;

grant execute on function syl_may_read(uuid) to anon, authenticated;

drop policy if exists syl_drops_read  on syl_drops;
drop policy if exists syl_raids_read  on syl_raids;
drop policy if exists syl_guilds_read on syl_guilds;

create policy syl_drops_read on syl_drops
    for select to authenticated
    using (syl_may_read(guild_id));

create policy syl_raids_read on syl_raids
    for select to authenticated
    using (syl_may_read(guild_id));

create policy syl_guilds_read on syl_guilds
    for select to authenticated
    using (syl_may_read(id));

-- You can see which addresses are authorised for a guild you can read, so the
-- page can show who has access. Still read-only from the browser.
drop policy if exists syl_allowed_read on syl_allowed;

create policy syl_allowed_read on syl_allowed
    for select to authenticated
    using (syl_may_read(guild_id));

-- ---------------------------------------------------------------------------
-- Authorising people
-- ---------------------------------------------------------------------------
--
-- Add one or many. They do not need to have signed in yet.
--
--   insert into syl_allowed (guild_id, email)
--   select g.id, lower(e)
--   from syl_guilds g,
--        unnest(array[
--          'someone@example.com',
--          'another@example.com'
--        ]) as e
--   where g.name = 'Show Us Your Kitties'
--   on conflict do nothing;
--
-- Revoke:
--
--   delete from syl_allowed where lower(email) = lower('someone@example.com');
--
-- See who has access:
--
--   select email, role, added_at from syl_allowed order by added_at;
