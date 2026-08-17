do $$
begin
  if exists (select 1 from store_product_versions
              where fulfillment_type = 'LIMITED_BENEFIT') then
    raise exception 'cannot rollback V12 while limited benefit product versions exist';
  end if;
end
$$;

alter table store_product_versions
    drop constraint store_product_versions_fulfillment_payload_check;

alter table store_product_versions alter column reward_asset_type set not null;
alter table store_product_versions alter column reward_asset_code set not null;
alter table store_product_versions alter column reward_amount set not null;

alter table store_product_versions
    add constraint store_product_versions_reward_asset_type_check
        check (reward_asset_type in ('CURRENCY'));
alter table store_product_versions
    add constraint store_product_versions_reward_asset_code_check
        check (reward_asset_code ~ '^[A-Z][A-Z0-9_]{1,39}$');
alter table store_product_versions
    add constraint store_product_versions_reward_amount_check
        check (reward_amount > 0);

comment on column store_product_versions.fulfillment_type is null;
