--Задание 1
INSERT INTO orders
    (order_id, order_dt, user_id, device_type, city_id, total_cost, discount, 
    final_cost)
SELECT MAX(order_id) + 1, current_timestamp, 
    '329551a1-215d-43e6-baee-322f2467272d', 
    'Mobile', 1, 1000.00, null, 1000.00
FROM orders;
--ПОЯСНЕНИЕ 
-- 1) - order_id не являетсяя primary_key 
-- 2) - order_dt по умолчанию можно прописать current_timestamp не указывая явно
-- 3) - discount можно указать 0 по умолчанию
-- Установка первичного ключа для order_id
ALTER TABLE orders 
ADD PRIMARY KEY (order_id);

-- Установка значения по умолчанию для order_dt
ALTER TABLE orders 
ALTER COLUMN order_dt 
SET DEFAULT CURRENT_TIMESTAMP;

-- Установка значения по умолчанию для discount
ALTER TABLE orders 
ALTER COLUMN discount 
SET DEFAULT 0;
-- РЕШЕНИЕ теперь можно использовать такую вставку
INSERT INTO orders (user_id, device_type, city_id, total_cost, final_cost)
VALUES ('329551a1-215d-43e6-baee-322f2467272d', 'Mobile', 1, 1000.00, 1000.00);
-- Так же можно удалить лишнии индексы так как они далее не понадобятся, на производительности запроса это не отразится, но место на диске освободится.
DROP INDEX orders_total_final_cost_discount_idx,
           orders_total_cost_idx,
           orders_order_dt_idx,
           orders_final_cost_idx,
           orders_discount_idx,
           orders_device_type_idx,
           orders_device_type_city_id_idx

--Задание 2
SELECT user_id::text::uuid, first_name::text, last_name::text, 
    city_id::bigint, gender::text
FROM users
WHERE city_id::integer = 4
    AND date_part('day', to_date(birth_date::text, 'yyyy-mm-dd')) 
        = date_part('day', to_date('31-12-2023', 'dd-mm-yyyy'))
    AND date_part('month', to_date(birth_date::text, 'yyyy-mm-dd')) 
        = date_part('month', to_date('31-12-2023', 'dd-mm-yyyy')) 
--Пояснение
-- 1) Вся таблица users спроектированна не правильно, исправим это
-- Преобразование в VARCHAR
ALTER TABLE users
ALTER COLUMN user_id
SET DATA TYPE VARCHAR(255);

ALTER TABLE users 
ALTER COLUMN user_id 
SET DATA TYPE uuid USING user_id::uuid;

ALTER TABLE users
ALTER COLUMN first_name
SET DATA TYPE VARCHAR(50);

ALTER TABLE users
ALTER COLUMN last_name
SET DATA TYPE VARCHAR(50);

ALTER TABLE users
ALTER COLUMN gender
SET DATA TYPE VARCHAR(20);

-- Создаем тип данных для поля gender
CREATE TYPE gender_type AS ENUM ('male', 'female');

ALTER TABLE users
ALTER COLUMN gender
SET DATA TYPE gender_type USING gender::gender_type;

-- Изменение типа данных для birth_date и registration_date на DATE
ALTER TABLE users
ALTER COLUMN birth_date
SET DATA TYPE DATE USING birth_date::date;

ALTER TABLE users
ALTER COLUMN registration_date
SET DATA TYPE DATE USING registration_date::date;

-- Установка city_id в качестве первичного ключа в таблице cities
ALTER TABLE cities
ADD PRIMARY KEY (city_id);

-- Изменение типа данных для city_id на integer
ALTER TABLE users
ALTER COLUMN city_id
SET DATA TYPE integer;

-- Ставим NULL если id города 0 - такого нет в таблице городов
UPDATE users SET city_id = NULL where city_id = 0
-- Добаляем внешний ключ
ALTER TABLE users
ADD CONSTRAINT fk_city
FOREIGN KEY (city_id) REFERENCES cities(city_id);

-- РЕШЕНИЕ 
-- Теперь можно запрос скорректировать на такой:
SELECT user_id, first_name, last_name, city_id, gender
FROM users
WHERE city_id = 4
    AND EXTRACT(day FROM birth_date) = 31
    AND EXTRACT(month FROM birth_date) = 12;

-- Задание 3
--Тут поможет создание индексов на все основные id столбцы а так же модификация колонко таблиц с которыми взаимодействует процедура

--Решение
-- Добавим внешние ключи
ALTER TABLE payments
ADD CONSTRAINT fk_payment_id
FOREIGN KEY (payment_id) REFERENCES payments(payment_id);

ALTER TABLE statuses
ADD CONSTRAINT fk_status_id
FOREIGN KEY (status_id) REFERENCES statuses(status_id);

ALTER TABLE sales
ADD CONSTRAINT fk_sale_id
FOREIGN KEY (sale_id) REFERENCES sales(sale_id);
--Добавим индексы
CREATE INDEX idx_payments_payment_id ON payments (payment_id);
CREATE INDEX idx_statuses_status_id ON statuses (status_id);
-- Обновленный код процедуры будет выглядить так:
    -- Вставка статуса заказа
    INSERT INTO order_statuses (order_id, status_id, status_dt)
    VALUES (p_order_id, 2, statement_timestamp());
    
    -- Вставка платежа
    INSERT INTO payments (order_id, payment_sum)
    VALUES (p_order_id, p_sum_payment);
-- Таблица sales избыточна, нужные данные есть в payments b order_statuses
-- sales можно заполнить треггером например или удалить ее вообще.

-- Задание 4
-- Проблему можно постараться решить партицированием таблицы
-- Для 2024 года
CREATE TABLE user_logs_2024 PARTITION OF user_logs
FOR VALUES FROM ('2024-01-01') TO ('2025-01-01');
-- Для 2023 года
CREATE TABLE user_logs_2023 PARTITION OF user_logs
FOR VALUES FROM ('2023-01-01') TO ('2024-01-01');

-- Для для 2022 года и т.д.
CREATE TABLE user_logs_2022 PARTITION OF user_logs
FOR VALUES FROM ('2022-01-01') TO ('2023-01-01');
-- и тд 

-- Задание 5 
-- Проблему можно решить созданием материализованного представления для отчета
CREATE MATERIALIZED VIEW report_preferences_by_age AS
SELECT
    CASE
        WHEN DATE_PART('year', AGE(CURRENT_DATE, u.birth_date)) < 20 THEN '0–20'
        WHEN DATE_PART('year', AGE(CURRENT_DATE, u.birth_date)) < 30 THEN '20–30'
        WHEN DATE_PART('year', AGE(CURRENT_DATE, u.birth_date)) < 40 THEN '30–40'
        ELSE '40–100'
    END AS age_group,
    (SUM(d.spicy) * 100.0 / COUNT(*)) AS spicy_percentage,
    (SUM(d.fish) * 100.0 / COUNT(*)) AS fish_percentage,
    (SUM(d.meat) * 100.0 / COUNT(*)) AS meat_percentage
FROM
    orders o
JOIN
    users u ON o.user_id = u.user_id
JOIN
    order_items oi ON o.order_id = oi.order_id
JOIN
    dishes d ON oi.item = d.object_id
GROUP BY
    age_group
ORDER BY
    age_group;

SELECT * FROM report_preferences_by_age




