create table legal_documents (
    id uuid primary key,
    document_type varchar(30) not null
        check (document_type in ('PRIVACY_POLICY', 'TERMS_OF_SERVICE')),
    locale varchar(16) not null,
    version varchar(40) not null,
    title varchar(200) not null,
    content text not null,
    effective_at timestamptz not null,
    published_at timestamptz not null default now(),
    active boolean not null default false,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (document_type, locale, version),
    check (locale ~ '^[a-z]{2}(-[a-z0-9]{2,8})?$'),
    check (char_length(trim(version)) > 0),
    check (char_length(trim(title)) > 0),
    check (char_length(trim(content)) > 0)
);

create unique index legal_documents_one_active_locale_idx
    on legal_documents (document_type, locale)
    where active;

create index legal_documents_lookup_idx
    on legal_documents (document_type, locale, active, effective_at desc);
