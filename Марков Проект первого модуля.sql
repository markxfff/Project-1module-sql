/* Проект «real_estate»
 * Цель проекта: изучить данные архива сервиса Яндекс Недвижимость: здесь находятся объявления о продаже квартир 
 * в Санкт-Петербурге и Ленинградской области за несколько лет. 
 * 
 * Автор: Марков Максим Леонидович
 * Дата: 05.06.2025
*/

-- title: Задача 1. Время активности объявлений

WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats     
),
-- Вывод id объявлений, которые не содержат выбросы:
filtered_id AS(
    SELECT id
    FROM real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
        AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
    ),
-- таблица без аномалий:
filt_flats as (SELECT *
FROM real_estate.flats
WHERE id in (SELECT * FROM filtered_id)
),
-- градация по региону и времени размещения:
grade as (SELECT
	CASE 
		WHEN c.city = 'Санкт-Петербург'
		THEN 'Санкт-Петербург'
		ELSE 'Лен.Область'
	END AS region,
	CASE
		WHEN a.days_exposition BETWEEN 1 AND 30	THEN 'до месяца'
		WHEN a.days_exposition BETWEEN 31 AND 90 THEN 'до трех месяцев'
		WHEN a.days_exposition BETWEEN 91 AND 180 THEN 'до полугода'
		WHEN a.days_exposition > 180 THEN 'более полугода'
	END as time_interval, 
	f.id,
	f.total_area,
	f.living_area,
	f.kitchen_area,
	a.last_price / f.total_area AS price_per_meter,
	f.rooms,
	f.ceiling_height,
	f.balcony,
	f.floor,
	f.is_apartment,
	f.floors_total,
	f.open_plan,
	f.parks_around3000,
	f.ponds_around3000
FROM filt_flats f
LEFT JOIN real_estate.advertisement a USING(id)
LEFT JOIN real_estate.city c USING(city_id)
LEFT JOIN real_estate.type t USING(type_id)
WHERE t.type = 'город'
	AND a.days_exposition IS NOT NULL)
-- основной запрос с расчетами:
SELECT 
	region,
	time_interval,
	COUNT(id) AS count_ads,
	ROUND(COUNT(id)/SUM(COUNT(id)::NUMERIC) OVER(PARTITION BY region)*100) AS ads_perc, --доля ко количеству объявлений для региона
	ROUND(AVG(total_area::NUMERIC), 2) AS avg_area,
	ROUND(AVG(living_area::NUMERIC), 2) AS avg_living_area,
	ROUND(AVG(kitchen_area::NUMERIC), 2) AS avg_kitchen_area,
	ROUND(AVG(price_per_meter::NUMERIC), 2) AS avg_price_per_meter,
	PERCENTILE_DISC(0.5) WITHIN GROUP(ORDER BY price_per_meter) AS median_price_per_meter,
	ROUND(AVG(rooms::NUMERIC)) AS avg_rooms,
	PERCENTILE_CONT(0.5) WITHIN GROUP(ORDER BY rooms) AS median_rooms,
	ROUND(AVG(ceiling_height::NUMERIC),2) AS avg_ceiling_height,
	PERCENTILE_DISC(0.5) WITHIN GROUP(ORDER BY ceiling_height) AS median_ceiling_height,
	ROUND(AVG(floors_total::NUMERIC)) AS avg_house_floors,
	PERCENTILE_CONT(0.5) WITHIN GROUP(ORDER BY floors_total) AS median_house_floors,
	ROUND(AVG(floor::NUMERIC)) AS avg_floor,
	PERCENTILE_CONT(0.5) WITHIN GROUP(ORDER BY floor) AS median_floor,
	ROUND(AVG(balcony::NUMERIC)) AS avg_balcony,
	PERCENTILE_CONT(0.5) WITHIN GROUP(ORDER BY balcony) AS median_balcony, --подумал, что для отчетности нужно для каждого показателя считать и среднее и медиану (хотя, так как мы вначале фильтруем аномальные значения, медиану можно отбросить...)
	SUM(open_plan) as count_open_plan, -- количество объявлений с открытой планировкой 
	PERCENTILE_CONT(0.5) WITHIN GROUP(ORDER BY parks_around3000) AS median_parks3k,
	PERCENTILE_CONT(0.5) WITHIN GROUP(ORDER BY ponds_around3000) AS median_ponds3k   -- с прудами и парками явно вряд ли нужно считать и среднее и медиану одновременно (решил взять только медиану, как более точный расчет)
FROM grade
GROUP BY region, time_interval
ORDER BY region DESC, time_interval;

-- title: Задача 2. Сезонность объявлений

WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats     
),
-- Вывод id объявлений, которые не содержат выбросы:
filtered_id AS(
    SELECT id
    FROM real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
        AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
    ),
-- таблица без аномалий:
filt_flats as (SELECT *
FROM real_estate.flats
WHERE id in (SELECT * FROM filtered_id)
),

ads as (SELECT 
	a.id,
	EXTRACT(MONTH FROM a.first_day_exposition) AS month_of_publication,
	EXTRACT(MONTH FROM(a.first_day_exposition + (a.days_exposition * '1 day'::INTERVAL))) AS month_of_sale, --выделение месяца из даты публикации и снятия объявления 
	a.last_price,
	f.total_area,
	a.last_price / f.total_area AS price_per_meter
FROM real_estate.advertisement a
RIGHT JOIN filt_flats f USING(id)
JOIN real_estate.type t USING(type_id) 
--WHERE days_exposition IS NOT NULL 
	where t.type = 'город'
	AND EXTRACT(YEAR FROM a.first_day_exposition) BETWEEN 2015 AND 2018), -- за 2014 и 2019 неполные данные
	
calc_pub as (SELECT 
	month_of_publication AS month,
	COUNT(id) AS count_publication,
	AVG(price_per_meter) AS avg_price_per_meter,
	AVG(total_area) AS avg_total_area
FROM ads 
GROUP BY month_of_publication
),

calc_sale as (select
	month_of_sale AS month,
	COUNT(id) AS count_sale,
	AVG(price_per_meter) AS avg_price_per_meter2,
	AVG(total_area) AS avg_total_area2
FROM ads as ad 
join real_estate.advertisement as a using(id)
WHERE days_exposition IS NOT null --исправил замечание, что для опубликованных в days_exposition входят null
GROUP BY month_of_sale
)

SELECT
    p.month,
    p.count_publication,
	s.count_sale,
    RANK() OVER(ORDER BY count_publication DESC) AS publication_rank,
	RANK() OVER(ORDER BY count_sale DESC) AS sale_rank,
	ROUND((p.avg_price_per_meter::numeric), 2) as avg_price_per_meter_pub,
	ROUND((s.avg_price_per_meter2::NUMERIC),2) as avg_price_per_meter_sale,
	ROUND((p.avg_total_area::numeric), 2) as avg_total_area_pub,
	ROUND((s.avg_total_area2::NUMERIC),2) as avg_total_area_sale,
	ROUND(count_publication / SUM(count_publication::NUMERIC) OVER() * 100, 2) AS pub_perc,
	ROUND(count_sale / SUM(count_sale::NUMERIC) OVER() * 100, 2) AS sale_perc
	FROM calc_pub p
	FULL JOIN calc_sale s USING(month)
	order by month;

-- title: Задача 3. Анализ рынка недвижимости Ленобласти

WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats     
),
-- Вывод id объявлений, которые не содержат выбросы:
filtered_id as (SELECT id
    FROM real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
        AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
    ),
-- таблица без аномалий:
filt_flats as (SELECT *
FROM real_estate.flats
WHERE id in (SELECT * FROM filtered_id)
),
--начальные расчеты с фильтром на город
calc1 as (SELECT
	a.last_price / f.total_area AS price_per_meter,
	f.total_area,
	c.city,
	a.first_day_exposition,
	a.days_exposition
FROM filt_flats f 
LEFT JOIN real_estate.advertisement a USING(id)
LEFT JOIN real_estate.city c USING(city_id)
WHERE c.city <> 'Санкт-Петербург' 
)
-- итоговый запрос
select 
	city,
	COUNT(first_day_exposition) AS total_exposition,
	ROUND(COUNT(days_exposition)::NUMERIC / COUNT(first_day_exposition)*100,2) AS sale_perc,
	ROUND(AVG(price_per_meter::NUMERIC),2) AS avg_price_per_meter,
	ROUND(AVG(total_area::NUMERIC),2) AS avg_area,
	ROUND(AVG(days_exposition::NUMERIC)) AS sale_days
FROM calc1
GROUP BY city
HAVING COUNT(first_day_exposition) > 100 -- делаю фильтр на > 100 объявлений, так как таких населенных пунктов всего 15, и не нужно прописывать limit 15 (показывает самые популярные нас пункты)
ORDER BY total_exposition desc;




