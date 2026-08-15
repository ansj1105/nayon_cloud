create table player_accounts (
    id uuid primary key,
    public_id varchar(32) not null unique,
    status varchar(20) not null check (status in ('ACTIVE', 'SUSPENDED', 'DELETED')),
    nickname varchar(30) not null,
    avatar_code varchar(80),
    frame_code varchar(80),
    locale varchar(16),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    last_login_at timestamptz
);

create table auth_identities (
    id uuid primary key,
    account_id uuid not null unique
        references player_accounts(id) on delete restrict,
    provider varchar(20) not null check (provider in ('GOOGLE', 'APPLE')),
    provider_subject varchar(255) not null,
    email varchar(320),
    created_at timestamptz not null default now(),
    last_login_at timestamptz not null default now(),
    unique (provider, provider_subject)
);

create table player_save_states (
    account_id uuid primary key
        references player_accounts(id) on delete restrict,
    schema_version integer not null check (schema_version >= 1),
    revision bigint not null default 0 check (revision >= 0),
    payload jsonb not null default '{}'::jsonb,
    checksum varchar(64) not null check (char_length(checksum) = 64),
    client_build varchar(40) not null,
    updated_at timestamptz not null default now()
);

create table save_imports (
    id uuid primary key,
    account_id uuid not null
        references player_accounts(id) on delete restrict,
    request_id uuid not null unique,
    source_checksum varchar(64) not null unique
        check (char_length(source_checksum) = 64),
    status varchar(20) not null
        check (status in ('PENDING', 'COMPLETED', 'FAILED')),
    result jsonb,
    created_at timestamptz not null default now(),
    completed_at timestamptz,
    check (
        (status = 'COMPLETED' and completed_at is not null and result is not null)
        or (status <> 'COMPLETED')
    )
);

create index save_imports_account_created_idx
    on save_imports (account_id, created_at desc);
