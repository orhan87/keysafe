-- ============================================================
-- GOVDAG — Davet Sistemi
-- Versiyon: 1.0
-- ============================================================

-- ── DAVET TOKENLARI TABLOSU ──────────────────────────────────
create table public.invite_tokens (
  id          uuid primary key default uuid_generate_v4(),
  bureau_id   uuid not null references public.bureaus(id) on delete cascade,
  invited_by  uuid not null references auth.users(id),
  email       text not null,
  role        text not null default 'member'
              check (role in ('admin','member')),
  token       text not null unique default encode(gen_random_bytes(32),'hex'),
  used        boolean not null default false,
  expires_at  timestamptz not null default (now() + interval '7 days'),
  created_at  timestamptz not null default now()
);

alter table public.invite_tokens enable row level security;

-- Owner/admin kendi bürosunun davetlerini görebilir
create policy "invite_tokens: owner/admin okuyabilir"
  on public.invite_tokens for select
  using (get_my_role(bureau_id) in ('owner','admin'));

-- Owner/admin davet oluşturabilir
create policy "invite_tokens: owner/admin ekleyebilir"
  on public.invite_tokens for insert
  with check (get_my_role(bureau_id) in ('owner','admin'));

-- Token sahibi kullanıp işaretleyebilir (used=true)
create policy "invite_tokens: herkes guncelleyebilir"
  on public.invite_tokens for update
  using (true);

create index idx_invite_tokens_token   on public.invite_tokens(token);
create index idx_invite_tokens_email   on public.invite_tokens(email);
create index idx_invite_tokens_bureau  on public.invite_tokens(bureau_id);

-- ── TAMAMLANDI ───────────────────────────────────────────────
-- Sonraki adım: Supabase Edge Function oluştur (invite-user)
-- ============================================================
