-- Миграция 004 (уже применена): язык запроса кода, снимки цен в записях и заказах.
alter table public.code_requests add column lang text not null default 'ru';
alter table public.bookings add column price int;
alter table public.orders add column discount int not null default 0;
-- request_code(p_phone,p_name,p_lang): запоминает язык клиента, чтобы сообщение с кодом ушло на его языке.
-- trigger bookings_price: фиксирует цену услуги (с акцией и реферальной скидкой) в момент записи.
-- place_order: сохраняет в заказе название и цену каждой позиции на момент покупки и размер скидки.
