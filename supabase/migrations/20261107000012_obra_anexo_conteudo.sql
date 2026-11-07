-- Conteúdo de anexos pequenos guardado no próprio banco (base64), para arquivos carregados
-- direto pelo SQL, sem passar pelo Storage. O anexo aponta para cá com storage_path = 'db/<anexo_id>'.
set role obra_owner;

create table obra.anexo_conteudo (
  anexo_id uuid primary key references obra.anexo(id),
  base64 text not null,
  criado_em timestamptz not null default now()
);

alter table obra.anexo_conteudo enable row level security;

create policy anexo_conteudo_sel on obra.anexo_conteudo for select to authenticated
  using (exists (select 1 from obra.anexo a where a.id = anexo_conteudo.anexo_id and a.excluido_em is null and obra.eh_membro(a.obra_id)));

create policy anexo_conteudo_ins on obra.anexo_conteudo for insert to authenticated
  with check (exists (select 1 from obra.anexo a where a.id = anexo_conteudo.anexo_id and obra.eh_admin(a.obra_id)));

create trigger tg_anexo_conteudo_sem_delete before delete on obra.anexo_conteudo
  for each row execute function obra.tg_bloqueia_delete();

grant select, insert on obra.anexo_conteudo to authenticated;

reset role;
