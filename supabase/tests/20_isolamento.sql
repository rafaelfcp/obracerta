-- Prova de isolamento: o ObraCerta não consegue tocar no schema public (DashBoard-Financeiro).
\set ON_ERROR_STOP 1
select * from obra.verificar_isolamento();
do $$
declare v_falhas bigint;
begin
  select sum(ocorrencias) into v_falhas from obra.verificar_isolamento();
  if v_falhas <> 0 then raise exception 'FALHA: % ocorrência(s) de acoplamento com public', v_falhas; end if;
  raise notice 'OK catálogo: nenhum acoplamento obra -> public';
end $$;

-- O dono do schema (com quem as funções SECURITY DEFINER rodam) é barrado pelo banco no public
begin;
set local role obra_owner;
do $$
begin
  begin
    insert into public.lancamentos(descricao, valor) values ('tentativa', 1);
    raise exception 'FALHA: obra_owner gravou no public';
  exception when insufficient_privilege then null; end;
  begin
    perform count(*) from public.lancamentos;
    raise exception 'FALHA: obra_owner leu o public';
  exception when insufficient_privilege then null; end;
  begin
    update public.lancamentos set valor = 0;
    raise exception 'FALHA: obra_owner alterou o public';
  exception when insufficient_privilege then null; end;
  raise notice 'OK obra_owner: sem leitura, inserção ou alteração no public';
end $$;
rollback;

select count(*) as lancamentos_intactos from public.lancamentos;
