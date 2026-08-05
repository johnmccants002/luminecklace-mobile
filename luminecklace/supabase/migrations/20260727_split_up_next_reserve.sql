-- Ordered sender queue contract: Current -> Up Next -> Reserve.
-- API routes must call these primitives from trusted server code. The legacy
-- Reserve approval/catalog feature is intentionally not materialized here.

alter table public.necklaces
    add column if not exists queue_revision bigint not null default 0;

alter table public.messages
    add column if not exists queue_section text,
    add column if not exists queue_position int;

do $$
begin
    if not exists (
        select 1
        from pg_constraint
        where conname = 'messages_queue_section_check'
    ) then
        alter table public.messages
            add constraint messages_queue_section_check
            check (queue_section is null or queue_section in ('current', 'up_next', 'reserve'));
    end if;

    if not exists (
        select 1
        from pg_constraint
        where conname = 'messages_queue_position_check'
    ) then
        alter table public.messages
            add constraint messages_queue_position_check
            check (
                (queue_section = 'current' and queue_position is null)
                or (queue_section in ('up_next', 'reserve') and queue_position >= 0)
                or (queue_section is null and queue_position is null)
            );
    end if;
end $$;

-- Existing published order becomes one current message followed by Up Next.
-- No legacy Reserve catalog/approval rows are copied into the editable Reserve.
with ranked as (
    select
        id,
        row_number() over (
            partition by necklace_id
            order by queue_order asc nulls last, published_at asc nulls last, created_at asc
        ) - 1 as position
    from public.messages
    where state = 'published'
      and queue_section is null
)
update public.messages m
set queue_section = case when ranked.position = 0 then 'current' else 'up_next' end,
    queue_position = case when ranked.position = 0 then null else ranked.position - 1 end
from ranked
where ranked.id = m.id;

create unique index if not exists messages_one_current_per_necklace
    on public.messages (necklace_id)
    where state = 'published' and queue_section = 'current';

create unique index if not exists messages_unique_section_position
    on public.messages (necklace_id, queue_section, queue_position)
    where state = 'published' and queue_section in ('up_next', 'reserve');

create index if not exists messages_ordered_queue_lookup
    on public.messages (necklace_id, queue_section, queue_position)
    where state = 'published';

create or replace function public.sender_queue_snapshot(p_necklace_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
    select jsonb_build_object(
        'revision', n.queue_revision,
        'current', (
            select jsonb_build_object(
                'id', m.id,
                'text', m.content,
                'presentation', jsonb_build_object(
                    'theme', m.theme_key,
                    'animation', m.animation_key,
                    'sound', m.sound_key
                )
            )
            from public.messages m
            where m.necklace_id = n.id
              and m.state = 'published'
              and m.queue_section = 'current'
            limit 1
        ),
        'upNext', coalesce((
            select jsonb_agg(
                jsonb_build_object(
                    'id', m.id,
                    'text', m.content,
                    'presentation', jsonb_build_object(
                        'theme', m.theme_key,
                        'animation', m.animation_key,
                        'sound', m.sound_key
                    )
                )
                order by m.queue_position
            )
            from public.messages m
            where m.necklace_id = n.id
              and m.state = 'published'
              and m.queue_section = 'up_next'
        ), '[]'::jsonb),
        'reserve', coalesce((
            select jsonb_agg(
                jsonb_build_object(
                    'id', m.id,
                    'text', m.content,
                    'presentation', jsonb_build_object(
                        'theme', m.theme_key,
                        'animation', m.animation_key,
                        'sound', m.sound_key
                    )
                )
                order by m.queue_position
            )
            from public.messages m
            where m.necklace_id = n.id
              and m.state = 'published'
              and m.queue_section = 'reserve'
        ), '[]'::jsonb)
    )
    from public.necklaces n
    where n.id = p_necklace_id
      and exists (
          select 1
          from public.necklace_ownerships own
          where own.necklace_id = n.id
            and own.sender_user_id = auth.uid()
      );
$$;

create table if not exists public.queue_mutation_receipts (
    necklace_id uuid not null references public.necklaces (id) on delete cascade,
    idempotency_key uuid not null,
    response jsonb not null,
    created_at timestamptz not null default now(),
    primary key (necklace_id, idempotency_key)
);

alter table public.queue_mutation_receipts enable row level security;

create or replace function public.mutate_sender_queue(
    p_necklace_id uuid,
    p_expected_revision bigint,
    p_idempotency_key uuid,
    p_operation jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    current_revision bigint;
    operation_type text := p_operation->>'type';
    source_section text;
    destination_section text;
    placement text;
    message_id uuid;
    ordered_ids jsonb;
    response jsonb;
    actual_count int;
begin
    if not exists (
        select 1
        from public.necklace_ownerships own
        where own.necklace_id = p_necklace_id
          and own.sender_user_id = auth.uid()
    ) then
        raise exception 'unauthorized';
    end if;

    select r.response
    into response
    from public.queue_mutation_receipts r
    where r.necklace_id = p_necklace_id
      and r.idempotency_key = p_idempotency_key;
    if response is not null then
        return response;
    end if;

    select queue_revision
    into current_revision
    from public.necklaces
    where id = p_necklace_id
    for update;

    if current_revision is distinct from p_expected_revision then
        raise exception using
            errcode = '40001',
            message = 'queue_revision_conflict',
            detail = public.sender_queue_snapshot(p_necklace_id)::text;
    end if;

    if operation_type = 'reorder' then
        source_section := p_operation->>'section';
        ordered_ids := p_operation->'orderedMessageIds';
        if source_section not in ('up_next', 'reserve')
           or jsonb_typeof(ordered_ids) is distinct from 'array' then
            raise exception 'invalid_reorder';
        end if;

        select count(*)
        into actual_count
        from public.messages
        where necklace_id = p_necklace_id
          and state = 'published'
          and queue_section = source_section;

        if actual_count <> jsonb_array_length(ordered_ids)
           or actual_count <> (
               select count(distinct value)
               from jsonb_array_elements_text(ordered_ids)
           )
           or exists (
               select 1
               from jsonb_array_elements_text(ordered_ids) requested(value)
               left join public.messages m
                 on m.id = requested.value::uuid
                and m.necklace_id = p_necklace_id
                and m.state = 'published'
                and m.queue_section = source_section
               where m.id is null
           ) then
            raise exception 'reorder_membership_mismatch';
        end if;

        with requested as (
            select value::uuid as id, ordinality::int - 1 as new_position
            from jsonb_array_elements_text(ordered_ids) with ordinality
        )
        update public.messages m
        set queue_position = -1 - requested.new_position
        from requested
        where requested.id = m.id;

        update public.messages
        set queue_position = -1 - queue_position
        where necklace_id = p_necklace_id
          and state = 'published'
          and queue_section = source_section;

    elsif operation_type = 'move' then
        message_id := (p_operation->>'messageId')::uuid;
        destination_section := p_operation->>'destination';
        placement := p_operation->>'placement';
        if destination_section not in ('up_next', 'reserve')
           or placement not in ('first', 'last') then
            raise exception 'invalid_move';
        end if;

        select queue_section
        into source_section
        from public.messages
        where id = message_id
          and necklace_id = p_necklace_id
          and state = 'published'
        for update;

        if source_section is null or source_section = 'current' then
            raise exception 'message_is_not_editable';
        end if;

        update public.messages
        set queue_section = null,
            queue_position = null
        where id = message_id;

        with compacted as (
            select id, row_number() over (order by queue_position)::int - 1 as new_position
            from public.messages
            where necklace_id = p_necklace_id
              and state = 'published'
              and queue_section = source_section
        )
        update public.messages m
        set queue_position = -1 - compacted.new_position
        from compacted
        where compacted.id = m.id;

        update public.messages
        set queue_position = -1 - queue_position
        where necklace_id = p_necklace_id
          and state = 'published'
          and queue_section = source_section;

        if placement = 'first' then
            update public.messages
            set queue_position = -2 - queue_position
            where necklace_id = p_necklace_id
              and state = 'published'
              and queue_section = destination_section;

            update public.messages
            set queue_position = -1 - queue_position
            where necklace_id = p_necklace_id
              and state = 'published'
              and queue_section = destination_section;
        end if;

        update public.messages
        set queue_section = destination_section,
            queue_position = case
                when placement = 'first' then 0
                else coalesce((
                    select max(m.queue_position) + 1
                    from public.messages m
                    where m.necklace_id = p_necklace_id
                      and m.state = 'published'
                      and m.queue_section = destination_section
                ), 0)
            end
        where id = message_id;

    elsif operation_type = 'remove' then
        message_id := (p_operation->>'messageId')::uuid;
        select queue_section
        into source_section
        from public.messages
        where id = message_id
          and necklace_id = p_necklace_id
          and state = 'published'
        for update;

        if source_section is null or source_section = 'current' then
            raise exception 'message_is_not_editable';
        end if;

        update public.messages
        set state = 'archived',
            queue_section = null,
            queue_position = null
        where id = message_id;

        with compacted as (
            select id, row_number() over (order by queue_position)::int - 1 as new_position
            from public.messages
            where necklace_id = p_necklace_id
              and state = 'published'
              and queue_section = source_section
        )
        update public.messages m
        set queue_position = -1 - compacted.new_position
        from compacted
        where compacted.id = m.id;

        update public.messages
        set queue_position = -1 - queue_position
        where necklace_id = p_necklace_id
          and state = 'published'
          and queue_section = source_section;
    else
        raise exception 'unsupported_queue_operation';
    end if;

    update public.necklaces
    set queue_revision = queue_revision + 1
    where id = p_necklace_id;

    response := public.sender_queue_snapshot(p_necklace_id);
    insert into public.queue_mutation_receipts (
        necklace_id,
        idempotency_key,
        response
    ) values (
        p_necklace_id,
        p_idempotency_key,
        response
    );

    return response;
end;
$$;

-- Called once, idempotently, by the reveal-confirmation transaction after the
-- current message is archived. It never moves Reserve into Up Next.
create or replace function public.advance_sender_queue(p_necklace_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    next_message_id uuid;
begin
    perform 1
    from public.necklaces
    where id = p_necklace_id
    for update;

    if exists (
        select 1 from public.messages
        where necklace_id = p_necklace_id
          and state = 'published'
          and queue_section = 'current'
    ) then
        raise exception 'current_message_must_be_consumed_first';
    end if;

    select id
    into next_message_id
    from public.messages
    where necklace_id = p_necklace_id
      and state = 'published'
      and queue_section = 'up_next'
    order by queue_position
    limit 1;

    if next_message_id is null then
        select id
        into next_message_id
        from public.messages
        where necklace_id = p_necklace_id
          and state = 'published'
          and queue_section = 'reserve'
        order by queue_position
        limit 1;
    end if;

    if next_message_id is not null then
        update public.messages
        set queue_section = 'current',
            queue_position = null
        where id = next_message_id;

        with compacted as (
            select
                id,
                row_number() over (
                    partition by queue_section
                    order by queue_position
                ) - 1 as new_position
            from public.messages
            where necklace_id = p_necklace_id
              and state = 'published'
              and queue_section in ('up_next', 'reserve')
        )
        update public.messages m
        set queue_position = -1 - compacted.new_position
        from compacted
        where compacted.id = m.id;

        update public.messages
        set queue_position = -1 - queue_position
        where necklace_id = p_necklace_id
          and state = 'published'
          and queue_section in ('up_next', 'reserve');
    end if;

    update public.necklaces
    set queue_revision = queue_revision + 1
    where id = p_necklace_id;

    return jsonb_build_object(
        'status', 'advanced',
        'revision', (
            select queue_revision
            from public.necklaces
            where id = p_necklace_id
        )
    );
end;
$$;
