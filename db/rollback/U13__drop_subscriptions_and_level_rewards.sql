do $$
begin
  if exists (
      select 1
        from store_products p
        join store_offers o on o.id = p.offer_id
       where o.offer_code in ('monthly_growth', 'monthly_advanced')) then
    raise exception 'cannot rollback V13 while subscription products exist';
  end if;
end
$$;

drop table if exists player_subscription_daily_rewards;
drop table if exists player_subscription_initial_rewards;
drop table if exists player_level_reward_claims;
drop table if exists level_reward_versions;
drop table if exists google_play_rtdn_events;
drop table if exists subscription_verification_requests;
drop table if exists player_subscriptions;
drop table if exists subscription_benefit_versions;
drop table if exists subscription_plans;

delete from store_offers
where offer_code in ('monthly_growth', 'monthly_advanced');

alter table store_product_versions
    drop constraint store_product_versions_fulfillment_payload_check;
alter table store_product_versions
    add constraint store_product_versions_fulfillment_payload_check check (
        (fulfillment_type = 'DIRECT_CURRENCY'
            and reward_asset_type = 'CURRENCY'
            and reward_asset_code is not null
            and reward_asset_code ~ '^[A-Z][A-Z0-9_]{1,39}$'
            and reward_amount > 0)
        or (fulfillment_type = 'LIMITED_BENEFIT'
            and reward_asset_type is null
            and reward_asset_code is null
            and reward_amount is null)
    );

alter table store_product_versions
    drop constraint store_product_versions_fulfillment_type_check;
alter table store_product_versions
    add constraint store_product_versions_fulfillment_type_check
        check (fulfillment_type in ('DIRECT_CURRENCY', 'LIMITED_BENEFIT'));

alter table store_products
    drop constraint store_products_product_type_check;
alter table store_products
    add constraint store_products_product_type_check
        check (product_type in ('ONE_TIME'));
