-- Fix for: function gen_salt(unknown) does not exist
--
-- Supabase installs pgcrypto into the `extensions` schema, but the original
-- functions pinned search_path to `public` alone, so crypt() and gen_salt()
-- were not visible inside them.
--
-- Safe to run on an existing project. It only replaces two functions; no
-- table or row is touched.

create extension if not exists pgcrypto with schema extensions;

create or replace function syl_create_guild(p_name text, p_key text)
returns uuid
language plpgsql
security definer
set search_path = public, extensions
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
set search_path = public, extensions
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

revoke execute on function syl_create_guild(text, text) from anon, authenticated;

-- Check it worked. Should return one row with a uuid.
-- select syl_create_guild('Show Us Your Kitties', 'paste-a-long-random-key-here');
