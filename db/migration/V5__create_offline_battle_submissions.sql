create table offline_play_budgets (
    account_id uuid primary key references player_accounts(id) on delete restrict,
    window_id uuid not null unique,
    opened_at timestamptz not null,
    expires_at timestamptz not null,
    consumed_seconds bigint not null default 0 check (consumed_seconds >= 0),
    rules_version varchar(80) not null,
    rules_snapshot jsonb not null,
    version bigint not null default 0 check (version >= 0),
    updated_at timestamptz not null default now(),
    check (expires_at > opened_at)
);

create table offline_play_window_requests (
    id uuid primary key,
    account_id uuid not null references player_accounts(id) on delete restrict,
    request_id uuid not null,
    request_hash char(64) not null check (request_hash ~ '^[0-9a-f]{64}$'),
    window_id uuid not null,
    response_payload jsonb not null,
    created_at timestamptz not null default now(),
    unique (account_id, request_id)
);

create index offline_play_window_requests_account_created_idx
    on offline_play_window_requests (account_id, created_at desc, id desc);

create table offline_battle_submissions (
    id uuid primary key,
    account_id uuid not null references player_accounts(id) on delete restrict,
    request_id uuid not null,
    request_hash char(64) not null check (request_hash ~ '^[0-9a-f]{64}$'),
    window_id uuid not null,
    requested_seconds bigint not null check (requested_seconds >= 0),
    reward_state varchar(20) not null check (reward_state in ('GRANTED', 'HELD', 'REJECTED')),
    response_payload jsonb not null,
    created_at timestamptz not null default now(),
    unique (account_id, request_id)
);

alter table offline_battle_submissions
    add constraint offline_battle_submissions_id_account_uk
    unique (id, account_id);

create index offline_battle_submissions_account_created_idx
    on offline_battle_submissions (account_id, created_at desc, id desc);

create table offline_battle_runs (
    id uuid primary key,
    submission_id uuid not null,
    account_id uuid not null references player_accounts(id) on delete restrict,
    run_id uuid not null,
    stage_code varchar(80) not null,
    outcome varchar(20) not null check (outcome in ('CLEAR', 'LOSS', 'ABANDONED')),
    elapsed_seconds integer not null check (elapsed_seconds >= 0),
    kill_count integer not null check (kill_count >= 0),
    total_damage numeric(24,4) not null check (total_damage >= 0),
    reached_wave integer not null check (reached_wave >= 0),
    metrics_payload jsonb not null,
    created_at timestamptz not null default now(),
    unique (account_id, run_id),
    constraint offline_battle_runs_submission_account_fk
        foreign key (submission_id, account_id)
        references offline_battle_submissions(id, account_id) on delete restrict
);

create table offline_battle_decisions (
    id uuid primary key,
    run_id uuid not null unique references offline_battle_runs(id) on delete restrict,
    state varchar(20) not null check (state in ('GRANTED', 'HELD', 'REJECTED')),
    gold bigint not null default 0 check (gold >= 0),
    account_exp bigint not null default 0 check (account_exp >= 0),
    random_scroll bigint not null default 0 check (random_scroll >= 0),
    level_up_coupon bigint not null default 0 check (level_up_coupon >= 0),
    anomaly_reasons jsonb not null,
    decided_at timestamptz not null default now(),
    granted_at timestamptz
);

create index offline_battle_decisions_state_decided_idx
    on offline_battle_decisions (state, decided_at desc);
