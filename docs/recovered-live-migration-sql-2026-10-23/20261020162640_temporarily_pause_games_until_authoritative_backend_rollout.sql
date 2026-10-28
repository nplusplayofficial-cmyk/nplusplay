
begin;

do $precheck$
declare
  v_count integer;
begin
  select count(*) into v_count
  from public.game_settings
  where upper(game_key) in ('WINGO','K3','5D','TRX','AVIATOR','MOTO');

  if v_count <> 6 then
    raise exception 'Expected all six game settings before safe pause; found %.', v_count;
  end if;
end
$precheck$;

update public.game_settings
set enabled = false,
    updated_at = clock_timestamp()
where upper(game_key) in ('WINGO','K3','5D','TRX','AVIATOR','MOTO');

commit;
