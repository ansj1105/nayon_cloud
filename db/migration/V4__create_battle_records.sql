create table player_progression (
    account_id uuid primary key references player_accounts(id) on delete restrict,
    account_exp bigint not null default 0 check (account_exp >= 0),
    highest_stage_unlocked integer not null default 1 check (highest_stage_unlocked >= 1),
    version bigint not null default 0 check (version >= 0),
    updated_at timestamptz not null default now()
);

create table battle_sessions (
    id uuid primary key,
    account_id uuid not null references player_accounts(id) on delete restrict,
    request_id uuid not null,
    request_hash char(64) not null check (request_hash ~ '^[0-9a-f]{64}$'),
    stage_code varchar(80) not null,
    stage_snapshot jsonb not null,
    client_build varchar(40) not null,
    status varchar(20) not null check (status in ('ACTIVE', 'COMPLETED')),
    response_payload jsonb not null,
    started_at timestamptz not null,
    expires_at timestamptz not null,
    completed_at timestamptz,
    unique (account_id, request_id),
    check (expires_at > started_at),
    check ((status = 'ACTIVE' and completed_at is null)
        or (status = 'COMPLETED' and completed_at is not null))
);

create index battle_sessions_account_started_idx
    on battle_sessions (account_id, started_at desc, id desc);

create table battle_completions (
    id uuid primary key,
    battle_id uuid not null unique references battle_sessions(id) on delete restrict,
    account_id uuid not null references player_accounts(id) on delete restrict,
    request_id uuid not null,
    request_hash char(64) not null check (request_hash ~ '^[0-9a-f]{64}$'),
    outcome varchar(20) not null check (outcome in ('CLEAR', 'LOSS', 'ABANDONED')),
    elapsed_seconds integer not null,
    kill_count integer not null,
    total_damage numeric(24,4) not null,
    reached_wave integer not null,
    client_ended_at timestamptz not null,
    metrics_payload jsonb not null,
    response_payload jsonb not null,
    created_at timestamptz not null default now(),
    unique (account_id, request_id)
);

create table battle_anomalies (
    id uuid primary key,
    battle_id uuid not null references battle_sessions(id) on delete restrict,
    rule_code varchar(80) not null,
    severity varchar(20) not null check (severity in ('WARNING', 'CRITICAL')),
    observed_value varchar(160) not null,
    expected_value varchar(160) not null,
    details jsonb not null,
    created_at timestamptz not null default now(),
    unique (battle_id, rule_code)
);

create index battle_anomalies_rule_created_idx
    on battle_anomalies (rule_code, created_at desc);

create table battle_rewards (
    id uuid primary key,
    battle_id uuid not null unique references battle_sessions(id) on delete restrict,
    account_id uuid not null references player_accounts(id) on delete restrict,
    state varchar(20) not null check (state in ('GRANTED', 'HELD', 'REJECTED')),
    gold bigint not null default 0 check (gold >= 0),
    account_exp bigint not null default 0 check (account_exp >= 0),
    random_scroll bigint not null default 0 check (random_scroll >= 0),
    level_up_coupon bigint not null default 0 check (level_up_coupon >= 0),
    decision_details jsonb not null,
    decided_at timestamptz not null default now(),
    granted_at timestamptz
);

create index battle_rewards_account_decided_idx
    on battle_rewards (account_id, decided_at desc);
