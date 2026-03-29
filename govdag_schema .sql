-- ============================================================
-- GOVDAG — Supabase Veritabanı Şeması
-- Versiyon: 1.1 (sıralama düzeltildi)
-- Son güncelleme: 2026-03
-- ============================================================
-- Yapı: 1) Tablolar  2) RLS aktif  3) Policy'ler  4) Index'ler
-- ============================================================


-- ── UZANTI ──────────────────────────────────────────────────
create extension if not exists "uuid-ossp";


-- ════════════════════════════════════════════════════════════
-- BÖLÜM 1: TABLOLAR
-- ════════════════════════════════════════════════════════════

create table public.bureaus (
  id            uuid primary key default uuid_generate_v4(),
  name          text not null,
  slug          text unique not null,
  plan          text not null default 'trial'
                check (plan in ('trial','active','cancelled')),
  trial_ends_at timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create table public.bureau_members (
  id          uuid primary key default uuid_generate_v4(),
  bureau_id   uuid not null references public.bureaus(id) on delete cascade,
  user_id     uuid not null references auth.users(id) on delete cascade,
  role        text not null default 'member'
              check (role in ('owner','admin','member')),
  invited_by  uuid references auth.users(id),
  joined_at   timestamptz not null default now(),
  unique (bureau_id, user_id)
);

create table public.folders (
  id          uuid primary key default uuid_generate_v4(),
  bureau_id   uuid not null references public.bureaus(id) on delete cascade,
  name        text not null,
  description text,
  color       text,
  icon        text,
  sort_order  integer not null default 0,
  created_by  uuid references auth.users(id),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create table public.credentials (
  id              uuid primary key default uuid_generate_v4(),
  folder_id       uuid not null references public.folders(id) on delete cascade,
  bureau_id       uuid not null references public.bureaus(id) on delete cascade,
  site_name       text not null,
  site_url        text,
  category        text,
  label           text,
  encrypted_notes text,
  sort_order      integer not null default 0,
  created_by      uuid references auth.users(id),
  updated_by      uuid references auth.users(id),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

create table public.credential_fields (
  id              uuid primary key default uuid_generate_v4(),
  credential_id   uuid not null references public.credentials(id) on delete cascade,
  bureau_id       uuid not null references public.bureaus(id) on delete cascade,
  field_name      text not null,
  encrypted_value text not null,
  is_secret       boolean not null default true,
  sort_order      integer not null default 0,
  created_at      timestamptz not null default now()
);

create table public.subscriptions (
  id                     uuid primary key default uuid_generate_v4(),
  bureau_id              uuid not null references public.bureaus(id) on delete cascade,
  stripe_customer_id     text unique,
  stripe_subscription_id text unique,
  stripe_price_id        text,
  status                 text not null default 'trialing'
                         check (status in ('trialing','active','past_due','cancelled','incomplete')),
  current_period_start   timestamptz,
  current_period_end     timestamptz,
  cancel_at_period_end   boolean not null default false,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now()
);

create table public.audit_logs (
  id            uuid primary key default uuid_generate_v4(),
  bureau_id     uuid not null references public.bureaus(id) on delete cascade,
  user_id       uuid references auth.users(id),
  action        text not null,
  resource_type text,
  resource_id   uuid,
  resource_name text,
  ip_address    text,
  user_agent    text,
  created_at    timestamptz not null default now()
);


-- ════════════════════════════════════════════════════════════
-- BÖLÜM 2: RLS AKTİF
-- ════════════════════════════════════════════════════════════

alter table public.bureaus           enable row level security;
alter table public.bureau_members    enable row level security;
alter table public.folders           enable row level security;
alter table public.credentials       enable row level security;
alter table public.credential_fields enable row level security;
alter table public.subscriptions     enable row level security;
alter table public.audit_logs        enable row level security;


-- ════════════════════════════════════════════════════════════
-- BÖLÜM 3: POLICY'LER
-- ════════════════════════════════════════════════════════════

-- bureaus
create policy "bureaus: uye okuyabilir"
  on public.bureaus for select
  using (id in (select bureau_id from public.bureau_members where user_id = auth.uid()));

create policy "bureaus: owner guncelleyebilir"
  on public.bureaus for update
  using (id in (select bureau_id from public.bureau_members where user_id = auth.uid() and role = 'owner'));

-- bureau_members
create policy "bureau_members: uye okuyabilir"
  on public.bureau_members for select
  using (bureau_id in (select bureau_id from public.bureau_members where user_id = auth.uid()));

create policy "bureau_members: owner/admin ekleyebilir"
  on public.bureau_members for insert
  with check (bureau_id in (select bureau_id from public.bureau_members where user_id = auth.uid() and role in ('owner','admin')));

create policy "bureau_members: owner/admin silebilir"
  on public.bureau_members for delete
  using (
    bureau_id in (select bureau_id from public.bureau_members where user_id = auth.uid() and role in ('owner','admin'))
    and user_id != auth.uid()
  );

-- folders
create policy "folders: uye okuyabilir"
  on public.folders for select
  using (bureau_id in (select bureau_id from public.bureau_members where user_id = auth.uid()));

create policy "folders: uye ekleyebilir"
  on public.folders for insert
  with check (bureau_id in (select bureau_id from public.bureau_members where user_id = auth.uid()));

create policy "folders: uye guncelleyebilir"
  on public.folders for update
  using (bureau_id in (select bureau_id from public.bureau_members where user_id = auth.uid()));

create policy "folders: owner/admin silebilir"
  on public.folders for delete
  using (bureau_id in (select bureau_id from public.bureau_members where user_id = auth.uid() and role in ('owner','admin')));

-- credentials
create policy "credentials: uye okuyabilir"
  on public.credentials for select
  using (bureau_id in (select bureau_id from public.bureau_members where user_id = auth.uid()));

create policy "credentials: uye ekleyebilir"
  on public.credentials for insert
  with check (bureau_id in (select bureau_id from public.bureau_members where user_id = auth.uid()));

create policy "credentials: uye guncelleyebilir"
  on public.credentials for update
  using (bureau_id in (select bureau_id from public.bureau_members where user_id = auth.uid()));

create policy "credentials: owner/admin silebilir"
  on public.credentials for delete
  using (bureau_id in (select bureau_id from public.bureau_members where user_id = auth.uid() and role in ('owner','admin')));

-- credential_fields
create policy "credential_fields: uye okuyabilir"
  on public.credential_fields for select
  using (bureau_id in (select bureau_id from public.bureau_members where user_id = auth.uid()));

create policy "credential_fields: uye ekleyebilir"
  on public.credential_fields for insert
  with check (bureau_id in (select bureau_id from public.bureau_members where user_id = auth.uid()));

create policy "credential_fields: uye guncelleyebilir"
  on public.credential_fields for update
  using (bureau_id in (select bureau_id from public.bureau_members where user_id = auth.uid()));

create policy "credential_fields: uye silebilir"
  on public.credential_fields for delete
  using (bureau_id in (select bureau_id from public.bureau_members where user_id = auth.uid()));

-- subscriptions
create policy "subscriptions: owner okuyabilir"
  on public.subscriptions for select
  using (bureau_id in (select bureau_id from public.bureau_members where user_id = auth.uid() and role = 'owner'));

-- audit_logs
create policy "audit_logs: owner/admin okuyabilir"
  on public.audit_logs for select
  using (bureau_id in (select bureau_id from public.bureau_members where user_id = auth.uid() and role in ('owner','admin')));

create policy "audit_logs: uye ekleyebilir"
  on public.audit_logs for insert
  with check (bureau_id in (select bureau_id from public.bureau_members where user_id = auth.uid()));


-- ════════════════════════════════════════════════════════════
-- BÖLÜM 4: INDEX'LER
-- ════════════════════════════════════════════════════════════

create index idx_bureau_members_user      on public.bureau_members(user_id);
create index idx_bureau_members_bureau    on public.bureau_members(bureau_id);
create index idx_folders_bureau           on public.folders(bureau_id);
create index idx_credentials_folder       on public.credentials(folder_id);
create index idx_credentials_bureau       on public.credentials(bureau_id);
create index idx_credential_fields_cred   on public.credential_fields(credential_id);
create index idx_credential_fields_bureau on public.credential_fields(bureau_id);
create index idx_subscriptions_bureau     on public.subscriptions(bureau_id);
create index idx_audit_logs_bureau        on public.audit_logs(bureau_id);
create index idx_audit_logs_resource      on public.audit_logs(resource_id);
create index idx_audit_logs_created       on public.audit_logs(created_at desc);


-- ════════════════════════════════════════════════════════════
-- BÖLÜM 5: FONKSİYONLAR VE TRIGGER'LAR
-- ════════════════════════════════════════════════════════════

create or replace function public.get_my_role(p_bureau_id uuid)
returns text language sql security definer as $$
  select role from public.bureau_members
  where bureau_id = p_bureau_id and user_id = auth.uid()
  limit 1;
$$;

create or replace function public.handle_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger bureaus_updated_at
  before update on public.bureaus
  for each row execute function public.handle_updated_at();

create trigger folders_updated_at
  before update on public.folders
  for each row execute function public.handle_updated_at();

create trigger credentials_updated_at
  before update on public.credentials
  for each row execute function public.handle_updated_at();

create trigger subscriptions_updated_at
  before update on public.subscriptions
  for each row execute function public.handle_updated_at();

-- ════════════════════════════════════════════════════════════
-- TAMAMLANDI — sıradaki adım: login.html
-- ════════════════════════════════════════════════════════════
