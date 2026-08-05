-- Show Us Your Loot — Supabase schema
--
-- Run this once in the Supabase SQL editor (Database → SQL editor → New query).
--
-- Security model: officers share one key. The tables have row level security
-- on with no policies at all, so the public anon key cannot read or write
-- them directly. Everything goes through two SECURITY DEFINER functions that
-- check the shared key first. That keeps the secret out of the database rows
-- and means a leaked anon key on its own is useless.

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

create table if not exists syl_guilds (
    id          uuid primary key default gen_random_uuid(),
    name        text not null,
    key_hash    text not null,
    created_at  timestamptz not null default now()
);

create table if not exists syl_drops (
    guild_id        uuid not null references syl_guilds(id) on delete cascade,
    id              text not null,

    season_name     text,
    encounter_id    integer,
    encounter_name  text,
    difficulty_id   integer,
    difficulty_name text,
    instance_id     integer,
    instance_name   text,

    item_id         bigint,
    item_name       text,

    winner_name     text,
    winner_guid     text,
    winner_class    text,
    winner_state    integer,
    winner_roll     integer,
    winner_rank     text,

    all_passed      boolean,
    eligible_count  integer,

    occurred_at     timestamptz,
    date_text       text,

    -- The full per-player roll list. Absent on records that arrived through
    -- in-game officer sync, which carries headers only.
    rolls           jsonb not null default '[]'::jsonb,

    uploaded_by     text,
    updated_at      timestamptz not null default now(),

    primary key (guild_id, id)
);

create table if not exists syl_raids (
    guild_id        uuid not null references syl_guilds(id) on delete cascade,
    id              text not null,

    season_name     text,
    instance_name   text,
    difficulty_name text,

    started_at      timestamptz,
    ended_at        timestamptz,
    date_text       text,

    roster_count    integer,
    encounters      jsonb not null default '[]'::jsonb,
    roster          jsonb not null default '[]'::jsonb,

    uploaded_by     text,
    updated_at      timestamptz not null default now(),

    primary key (guild_id, id)
);

create index if not exists syl_drops_occurred_idx
    on syl_drops (guild_id, occurred_at desc);

create index if not exists syl_raids_started_idx
    on syl_raids (guild_id, started_at desc);

-- Locked down. No policies are defined, so nothing reaches these tables
-- except through the functions below.
alter table syl_guilds enable row level security;
alter table syl_drops  enable row level security;
alter table syl_raids  enable row level security;

-- ---------------------------------------------------------------------------
-- Key handling
-- ---------------------------------------------------------------------------

-- Call once per guild to mint a key. Keep the returned value: it is not
-- recoverable, only replaceable.
create or replace function syl_create_guild(p_name text, p_key text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
    v_id uuid;
begin
    insert into syl_guilds (name, key_hash)
    values (p_name, crypt(p_key, gen_salt('bf')))
    returning id into v_id;

    return v_id;
end;
$$;

create or replace function syl_guild_for_key(p_key text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
    v_id uuid;
begin
    select id into v_id
    from syl_guilds
    where key_hash = crypt(p_key, key_hash)
    limit 1;

    return v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Upload
-- ---------------------------------------------------------------------------

-- Takes the schema v1 document the addon produces and merges it.
--
-- Merge rule, matching the in-game sync: a record carrying a roll list always
-- beats one without, so a full capture is never overwritten by a header-only
-- record from another officer. Otherwise the newer upload wins.
create or replace function syl_upload(p_key text, p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    v_guild    uuid;
    v_season   jsonb;
    v_row      jsonb;
    v_by       text;
    v_drops    integer := 0;
    v_raids    integer := 0;
begin
    v_guild := syl_guild_for_key(p_key);

    if v_guild is null then
        raise exception 'unknown key';
    end if;

    if coalesce((p_payload ->> 'schemaVersion')::int, 0) <> 1 then
        raise exception 'unsupported schemaVersion';
    end if;

    v_by := p_payload ->> 'exportedBy';

    for v_season in select * from jsonb_array_elements(p_payload -> 'seasons')
    loop
        for v_row in
            select * from jsonb_array_elements(coalesce(v_season -> 'drops', '[]'::jsonb))
        loop
            insert into syl_drops as d (
                guild_id, id, season_name,
                encounter_id, encounter_name, difficulty_id, difficulty_name,
                instance_id, instance_name,
                item_id, item_name,
                winner_name, winner_guid, winner_class, winner_state,
                winner_roll, winner_rank,
                all_passed, eligible_count,
                occurred_at, date_text, rolls, uploaded_by, updated_at
            )
            values (
                v_guild,
                v_row ->> 'id',
                v_season ->> 'name',
                (v_row ->> 'encounterID')::int,
                v_row ->> 'encounterName',
                (v_row ->> 'difficultyID')::int,
                v_row ->> 'difficultyName',
                (v_row ->> 'instanceID')::int,
                v_row ->> 'instanceName',
                (v_row ->> 'itemID')::bigint,
                v_row ->> 'itemName',
                v_row ->> 'winnerName',
                v_row ->> 'winnerGUID',
                v_row ->> 'winnerClass',
                (v_row ->> 'winnerState')::int,
                (v_row ->> 'winnerRoll')::int,
                v_row ->> 'winnerGuildRank',
                coalesce((v_row ->> 'allPassed')::boolean, false),
                (v_row ->> 'eligibleCount')::int,
                to_timestamp((v_row ->> 'timestamp')::bigint),
                v_row ->> 'dateText',
                coalesce(v_row -> 'rolls', '[]'::jsonb),
                v_by,
                now()
            )
            on conflict (guild_id, id) do update set
                season_name     = excluded.season_name,
                encounter_name  = coalesce(excluded.encounter_name, d.encounter_name),
                difficulty_name = coalesce(excluded.difficulty_name, d.difficulty_name),
                instance_name   = coalesce(excluded.instance_name, d.instance_name),
                item_name       = coalesce(excluded.item_name, d.item_name),
                winner_name     = coalesce(excluded.winner_name, d.winner_name),
                winner_guid     = coalesce(excluded.winner_guid, d.winner_guid),
                winner_class    = coalesce(excluded.winner_class, d.winner_class),
                winner_state    = coalesce(excluded.winner_state, d.winner_state),
                winner_roll     = coalesce(excluded.winner_roll, d.winner_roll),
                winner_rank     = coalesce(excluded.winner_rank, d.winner_rank),
                eligible_count  = greatest(
                    coalesce(excluded.eligible_count, 0),
                    coalesce(d.eligible_count, 0)
                ),
                rolls           = excluded.rolls,
                uploaded_by     = excluded.uploaded_by,
                updated_at      = now()
            -- Never trade a full roll list for an empty one.
            where jsonb_array_length(excluded.rolls)
                  >= jsonb_array_length(d.rolls);

            v_drops := v_drops + 1;
        end loop;

        for v_row in
            select * from jsonb_array_elements(coalesce(v_season -> 'raids', '[]'::jsonb))
        loop
            insert into syl_raids as r (
                guild_id, id, season_name,
                instance_name, difficulty_name,
                started_at, ended_at, date_text,
                roster_count, encounters, roster, uploaded_by, updated_at
            )
            values (
                v_guild,
                v_row ->> 'id',
                v_season ->> 'name',
                v_row ->> 'instanceName',
                v_row ->> 'difficultyName',
                to_timestamp((v_row ->> 'startedAt')::bigint),
                to_timestamp((v_row ->> 'endedAt')::bigint),
                v_row ->> 'dateText',
                (v_row ->> 'rosterCount')::int,
                coalesce(v_row -> 'encounters', '[]'::jsonb),
                coalesce(v_row -> 'roster', '[]'::jsonb),
                v_by,
                now()
            )
            on conflict (guild_id, id) do update set
                ended_at     = greatest(excluded.ended_at, r.ended_at),
                roster_count = greatest(
                    coalesce(excluded.roster_count, 0),
                    coalesce(r.roster_count, 0)
                ),
                -- Keep whichever side saw more of the night.
                encounters   = case
                    when jsonb_array_length(excluded.encounters)
                         >= jsonb_array_length(r.encounters)
                    then excluded.encounters else r.encounters end,
                roster       = case
                    when jsonb_array_length(excluded.roster)
                         >= jsonb_array_length(r.roster)
                    then excluded.roster else r.roster end,
                uploaded_by  = excluded.uploaded_by,
                updated_at   = now();

            v_raids := v_raids + 1;
        end loop;
    end loop;

    return jsonb_build_object(
        'ok', true,
        'drops', v_drops,
        'raids', v_raids
    );
end;
$$;

-- ---------------------------------------------------------------------------
-- Fetch
-- ---------------------------------------------------------------------------

-- Returns everything for the guild behind the key, shaped like the addon's
-- own export so the dashboard can read either source unchanged.
create or replace function syl_fetch(p_key text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    v_guild uuid;
    v_name  text;
begin
    v_guild := syl_guild_for_key(p_key);

    if v_guild is null then
        raise exception 'unknown key';
    end if;

    select name into v_name from syl_guilds where id = v_guild;

    return jsonb_build_object(
        'schemaVersion', 1,
        'source', 'supabase',
        'guild', jsonb_build_object('name', v_name),
        'fetchedAt', extract(epoch from now())::bigint,
        'seasons', jsonb_build_array(
            jsonb_build_object(
                'name', coalesce(v_name, 'All data'),
                'active', true,
                'drops', coalesce((
                    select jsonb_agg(jsonb_build_object(
                        'id', id,
                        'encounterID', encounter_id,
                        'encounterName', encounter_name,
                        'difficultyID', difficulty_id,
                        'difficultyName', difficulty_name,
                        'instanceID', instance_id,
                        'instanceName', instance_name,
                        'itemID', item_id,
                        'itemName', item_name,
                        'winnerName', winner_name,
                        'winnerGUID', winner_guid,
                        'winnerClass', winner_class,
                        'winnerState', winner_state,
                        'winnerRoll', winner_roll,
                        'winnerGuildRank', winner_rank,
                        'allPassed', all_passed,
                        'eligibleCount', eligible_count,
                        'timestamp', extract(epoch from occurred_at)::bigint,
                        'dateText', date_text,
                        'rolls', rolls
                    ) order by occurred_at desc)
                    from syl_drops where guild_id = v_guild
                ), '[]'::jsonb),
                'raids', coalesce((
                    select jsonb_agg(jsonb_build_object(
                        'id', id,
                        'instanceName', instance_name,
                        'difficultyName', difficulty_name,
                        'startedAt', extract(epoch from started_at)::bigint,
                        'endedAt', extract(epoch from ended_at)::bigint,
                        'dateText', date_text,
                        'rosterCount', roster_count,
                        'encounters', encounters,
                        'roster', roster
                    ) order by started_at desc)
                    from syl_raids where guild_id = v_guild
                ), '[]'::jsonb),
                'loot', '[]'::jsonb
            )
        )
    );
end;
$$;

-- Anyone may call the two entry points; both refuse without a valid key.
grant execute on function syl_upload(text, jsonb) to anon, authenticated;
grant execute on function syl_fetch(text)         to anon, authenticated;

-- Deliberately NOT granted to anon: guild creation is a one-off you run here
-- in the SQL editor, not something the internet should be able to do.
revoke execute on function syl_create_guild(text, text) from anon, authenticated;

-- ---------------------------------------------------------------------------
-- One-off setup: mint your guild key, then keep the key somewhere safe.
-- ---------------------------------------------------------------------------
--
--   select syl_create_guild('Show Us Your Kitties', 'pick-a-long-random-key');
--
