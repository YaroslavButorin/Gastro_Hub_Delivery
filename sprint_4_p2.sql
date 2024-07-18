--Отбираем топ 5 медленных запроса
SELECT queryid,
       calls,
       total_exec_time,
       rows,
       query
FROM pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 5;

--- Результат:
-- №1
-- определяет количество неоплаченных заказов
SELECT count(*)
FROM order_statuses os
JOIN orders o ON o.order_id = os.order_id
WHERE (SELECT count(*)
	   FROM order_statuses os1
	   WHERE os1.order_id = o.order_id AND os1.status_id = $1) = $2
	AND o.city_id = $3
--№2
-- ищет логи за текущий день
SELECT *
FROM user_logs
WHERE datetime::date > current_date
--№3
-- ищет действия и время действия определенного посетителя
SELECT event, datetime
FROM user_logs
WHERE visitor_uuid = $1
ORDER BY 2
--№4
-- выводит данные о конкретном заказе: id, дату, стоимость и текущий статус
SELECT o.order_id, o.order_dt, o.final_cost, s.status_name
FROM order_statuses os
    JOIN orders o ON o.order_id = os.order_id
    JOIN statuses s ON s.status_id = os.status_id
WHERE o.user_id = $1::uuid
	AND os.status_dt IN (
	SELECT max(status_dt)
	FROM order_statuses
	WHERE order_id = o.order_id
    )
--№5
-- вычисляет количество заказов позиций, продажи которых выше среднего
SELECT d.name, SUM(count) AS orders_quantity
FROM order_items oi
    JOIN dishes d ON d.object_id = oi.item
WHERE oi.item IN (
	SELECT item
	FROM (SELECT item, SUM(count) AS total_sales
		  FROM order_items oi
		  GROUP BY 1) dishes_sales
	WHERE dishes_sales.total_sales > (
		SELECT SUM(t.total_sales)/ COUNT(*)
		FROM (SELECT item, SUM(count) AS total_sales
			FROM order_items oi
			GROUP BY
				1) t)
)
GROUP BY 1
ORDER BY orders_quantity DESC;

--====Оптимизация====
-- 1)
-- Сырой запрос "Execution Time: 61455.250 ms"

-- Добавим индексы все необходимые индексы
CREATE INDEX cities_city_id__idx ON cities(city_id);
CREATE INDEX order_statuses_order_id__idx ON order_statuses(order_id);
CREATE INDEX order_statuses_status_id__idx ON order_statuses(status_id);
CREATE INDEX orders_order_id_city_id__idx ON orders(order_id, city_id);
CREATE INDEX order_statuses_order_id_status_id__idx ON order_statuses(order_id, status_id);

-- Перепишем запрос c not exist
SELECT count(*)
FROM order_statuses os
JOIN orders o ON o.order_id = os.order_id
WHERE NOT EXISTS (SELECT 1
	   FROM order_statuses os1
	   WHERE os1.order_id = o.order_id AND os1.status_id = 2)
	AND o.city_id = 1;
--Результат 
--"Execution Time: 15.179 ms"

--2)
-- Сырой запрос "Execution Time: 2908.998 ms"

--Решение
SELECT *
FROM user_logs
WHERE datetime >= current_date AND datetime < current_date + interval '1 day';
-- не переводим datetime в тип date
--"Execution Time: 0.091 ms"

--3)
-- Сырой запрос "Execution Time: 305.853 ms"
--Решение
--Создадим индекс для visitor_uuid и datetime + на всех партициях. Не понятно почему но создавая индекс на главной таблице он не создается на партициях. Так и не понял этот момент буду рад если объяснишь как это должно работать
CREATE INDEX user_logs_visitor_uuid_datetime_idx ON user_logs(visitor_uuid,datetime);

CREATE INDEX user_logs_y2021q2_visitor_uuid_datetime_idx
ON user_logs_y2021q2 (visitor_uuid, datetime);

CREATE INDEX user_logs_y2021q3_visitor_uuid_datetime_idx
ON user_logs_y2021q3 (visitor_uuid, datetime);

CREATE INDEX user_logs_y2021q4_visitor_uuid_datetime_idx
ON user_logs_y2021q4 (visitor_uuid, datetime);

--"Execution Time: 0.131 ms"

--4)

--Сырой запрос "Execution Time: 101.851 ms"
-- Условие в where заменим на окнную функцию 
SELECT o.order_id, o.order_dt, o.final_cost, s.status_name
FROM (
    SELECT os.*,
           ROW_NUMBER() OVER (PARTITION BY os.order_id ORDER BY os.status_dt DESC) as rn
    FROM order_statuses os
) os
JOIN orders o ON o.order_id = os.order_id
JOIN statuses s ON s.status_id = os.status_id
WHERE o.user_id = 'c2885b45-dddd-4df3-b9b3-2cc012df727c'::uuid
AND os.rn = 1;
--"Execution Time: 47.704 ms"

--5)
--Сырой запрос "Execution Time: 78.187 ms"
--Добавим индекс на айтемы а так же на item и count
CREATE INDEX order_items_item_idx ON order_items(item);
CREATE INDEX idx_order_items_item_count ON order_items (item, count);

-- Оптимизированный запрос
WITH 
total_sales AS (
    SELECT item, SUM(count) AS total_sales
    FROM order_items
    GROUP BY item
),
average_sales AS (
    SELECT AVG(total_sales) AS avg_sales
    FROM total_sales
),
above_average_sales_items AS (
    SELECT item
    FROM total_sales
    WHERE total_sales > (SELECT avg_sales FROM average_sales)
)

SELECT d.name, SUM(count) AS orders_quantity
FROM order_items oi
JOIN dishes d ON d.object_id = oi.item
WHERE oi.item IN (SELECT item FROM above_average_sales_items)
GROUP BY 1
ORDER BY orders_quantity DESC

-- Заключение:
-- я постарался проанализировать бд 
-- В тех запросах где узлы стояли достаточно много и где сканировалось много строк через последовательное сканирование я старался применял индексы
-- Пробовал разные методы оптимизации запроса меняя условия where на join или применял CTE.