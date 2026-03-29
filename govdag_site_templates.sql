-- ============================================================
-- GOVDAG — Site Şablonları
-- Versiyon: 1.0
-- ============================================================
-- bureau_id NULL  = sistem şablonu (herkes görür, sadece admin düzenleyebilir)
-- bureau_id DOLU  = o büroya özel şablon (sadece o büro görür ve düzenler)
-- ============================================================

create table public.site_templates (
  id          uuid primary key default uuid_generate_v4(),
  bureau_id   uuid references public.bureaus(id) on delete cascade,
  category    text not null,
  site_name   text not null,
  site_url    text,
  fields      jsonb not null default '[]',
  -- fields örnek: [{"name":"TC Kimlik No","is_secret":false,"placeholder":"12345678901"},
  --                {"name":"Şifre","is_secret":true,"placeholder":""}]
  sort_order  integer not null default 0,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

alter table public.site_templates enable row level security;

-- Sistem şablonları (bureau_id null) herkes görebilir
create policy "site_templates: sistem sablonlari gorulur"
  on public.site_templates for select
  using (
    bureau_id is null
    or bureau_id in (select get_my_bureau_ids())
  );

-- Büro sahipleri/adminleri kendi şablonlarını ekleyebilir
create policy "site_templates: owner/admin ekleyebilir"
  on public.site_templates for insert
  with check (
    bureau_id is not null
    and get_my_role(bureau_id) in ('owner','admin')
  );

-- Büro sahipleri/adminleri kendi şablonlarını güncelleyebilir
create policy "site_templates: owner/admin guncelleyebilir"
  on public.site_templates for update
  using (
    bureau_id is not null
    and get_my_role(bureau_id) in ('owner','admin')
  );

-- Büro sahipleri/adminleri kendi şablonlarını silebilir
create policy "site_templates: owner/admin silebilir"
  on public.site_templates for delete
  using (
    bureau_id is not null
    and get_my_role(bureau_id) in ('owner','admin')
  );

create index idx_site_templates_bureau   on public.site_templates(bureau_id);
create index idx_site_templates_category on public.site_templates(category);

-- updated_at trigger
create trigger site_templates_updated_at
  before update on public.site_templates
  for each row execute function public.handle_updated_at();


-- ============================================================
-- SİSTEM ŞABLONLARI (bureau_id = null)
-- ============================================================

insert into public.site_templates (bureau_id, category, site_name, site_url, fields, sort_order) values

-- Vergi & SGK
(null, 'Vergi & SGK', 'Dijital Vergi Dairesi', 'dijitalvd.gib.gov.tr',
  '[{"name":"TC Kimlik No / VKN","is_secret":false,"placeholder":""},{"name":"Şifre","is_secret":true,"placeholder":""}]', 1),

(null, 'Vergi & SGK', 'İnteraktif Vergi Dairesi', 'ivd.gib.gov.tr',
  '[{"name":"TC Kimlik No","is_secret":false,"placeholder":""},{"name":"Şifre","is_secret":true,"placeholder":""}]', 2),

(null, 'Vergi & SGK', 'SGK e-Bildirge', 'uyg.sgk.gov.tr/ESBildirgesi',
  '[{"name":"TC Kimlik No","is_secret":false,"placeholder":""},{"name":"Şifre","is_secret":true,"placeholder":""},{"name":"İşyeri Sicil No","is_secret":false,"placeholder":""}]', 3),

(null, 'Vergi & SGK', 'SGK e-Hizmetler', 'uyg.sgk.gov.tr/EHizmetler',
  '[{"name":"TC Kimlik No","is_secret":false,"placeholder":""},{"name":"Şifre","is_secret":true,"placeholder":""}]', 4),

(null, 'Vergi & SGK', 'e-Devlet Kapısı', 'giris.turkiye.gov.tr',
  '[{"name":"TC Kimlik No","is_secret":false,"placeholder":""},{"name":"Şifre","is_secret":true,"placeholder":""}]', 5),

-- e-Fatura & KEP
(null, 'e-Fatura & KEP', 'GİB e-Fatura Portalı', 'efatura.gib.gov.tr',
  '[{"name":"Kullanıcı Adı","is_secret":false,"placeholder":""},{"name":"Şifre","is_secret":true,"placeholder":""}]', 10),

(null, 'e-Fatura & KEP', 'Logo e-Dönüşüm', 'logo.com.tr',
  '[{"name":"E-posta","is_secret":false,"placeholder":""},{"name":"Şifre","is_secret":true,"placeholder":""}]', 11),

(null, 'e-Fatura & KEP', 'Luca e-Dönüşüm', 'luca.com.tr',
  '[{"name":"E-posta","is_secret":false,"placeholder":""},{"name":"Şifre","is_secret":true,"placeholder":""}]', 12),

(null, 'e-Fatura & KEP', 'Turkcell KEP', 'turkcellkep.com.tr',
  '[{"name":"KEP Adresi","is_secret":false,"placeholder":"ad@hs03.kep.tr"},{"name":"Şifre","is_secret":true,"placeholder":""}]', 13),

(null, 'e-Fatura & KEP', 'PTT KEP', 'pttkep.com.tr',
  '[{"name":"KEP Adresi","is_secret":false,"placeholder":""},{"name":"Şifre","is_secret":true,"placeholder":""}]', 14),

(null, 'e-Fatura & KEP', 'TNB KEP', 'tnbkep.com.tr',
  '[{"name":"KEP Adresi","is_secret":false,"placeholder":""},{"name":"Şifre","is_secret":true,"placeholder":""}]', 15),

-- Ticaret Sicili
(null, 'Ticaret Sicili', 'MERSİS', 'mersis.gtb.gov.tr',
  '[{"name":"TC Kimlik No","is_secret":false,"placeholder":""},{"name":"Şifre","is_secret":true,"placeholder":""}]', 20),

(null, 'Ticaret Sicili', 'Ticaret Sicili Gazetesi', 'ticaretsicilgazetesi.gtb.gov.tr',
  '[{"name":"Kullanıcı Adı","is_secret":false,"placeholder":""},{"name":"Şifre","is_secret":true,"placeholder":""}]', 21),

(null, 'Ticaret Sicili', 'TOBB e-Portal', 'eportal.tobb.org.tr',
  '[{"name":"TC Kimlik No","is_secret":false,"placeholder":""},{"name":"Şifre","is_secret":true,"placeholder":""}]', 22),

-- Banka & Finans
(null, 'Banka & Finans', 'Ziraat Bankası Kurumsal', 'kurumsal.ziraatbank.com.tr',
  '[{"name":"Müşteri Numarası","is_secret":false,"placeholder":""},{"name":"Şifre","is_secret":true,"placeholder":""},{"name":"Şube Kodu","is_secret":false,"placeholder":""}]', 30),

(null, 'Banka & Finans', 'İş Bankası Kurumsal', 'kurumsal.isbank.com.tr',
  '[{"name":"Müşteri No","is_secret":false,"placeholder":""},{"name":"Şifre","is_secret":true,"placeholder":""}]', 31),

(null, 'Banka & Finans', 'Garanti BBVA Kurumsal', 'kurumsal.garantibbva.com.tr',
  '[{"name":"Müşteri No","is_secret":false,"placeholder":""},{"name":"Şifre","is_secret":true,"placeholder":""}]', 32),

(null, 'Banka & Finans', 'Halkbank Kurumsal', 'kurumsal.halkbank.com.tr',
  '[{"name":"Müşteri No","is_secret":false,"placeholder":""},{"name":"Şifre","is_secret":true,"placeholder":""}]', 33),

-- E-posta & İletişim
(null, 'E-posta & İletişim', 'Google Workspace', 'workspace.google.com',
  '[{"name":"E-posta","is_secret":false,"placeholder":""},{"name":"Şifre","is_secret":true,"placeholder":""}]', 40),

(null, 'E-posta & İletişim', 'Microsoft 365', 'portal.office.com',
  '[{"name":"E-posta","is_secret":false,"placeholder":""},{"name":"Şifre","is_secret":true,"placeholder":""}]', 41),

-- Diğer
(null, 'Diğer', 'Özel Giriş', null,
  '[{"name":"Kullanıcı Adı","is_secret":false,"placeholder":""},{"name":"Şifre","is_secret":true,"placeholder":""}]', 99);


-- ============================================================
-- TAMAMLANDI
-- ============================================================
