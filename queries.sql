/*Display the number of films in each category, sorted 
in descending order.*/
select count(film_category.film_id) as number_of_films, category.name as category
from film_category
join category on film_category.category_id = category.category_id
group by category.name order by number_of_films desc;

/*Display the top 10 actors whose films were rented the most, 
sorted in descending order.*/
select actor.first_name, actor.last_name, count(rental.rental_id) as rent
from rental 
join inventory on rental.inventory_id = inventory.inventory_id
join film on inventory.film_id = film.film_id
join film_actor on film.film_id = film_actor.film_id
join actor on film_actor.actor_id = actor.actor_id
group by actor.actor_id, actor.first_name, actor.last_name order by rent desc limit 10;

/*Display the category of films that generated the 
highest revenue.*/
select category.name as category, sum(payment.amount) as revenue
from category 
join film_category on category.category_id = film_category.category_id
join inventory on film_category.film_id = inventory.film_id
join rental on inventory.inventory_id = rental.inventory_id
join payment on rental.rental_id = payment.rental_id
group by category.name order by revenue desc limit 1;

/*Display the titles of films not present in the inventory. 
Write the query without using the IN operator.*/
select film.title as film_title
from film
left join inventory on film.film_id = inventory.film_id
where inventory.film_id is null;

/*Display the top 3 actors who appeared the most in films 
within the "Children" category. If multiple actors have the 
same count, include all*/
select ranked.first_name, ranked.last_name, ranked.number_of_films
from (
    select actor.actor_id,actor.first_name, actor.last_name,
        count(film_actor.film_id) as number_of_films,
        dense_rank() over (order by count(film_actor.film_id) desc) as film_rank
    from actor
    join film_actor on actor.actor_id = film_actor.actor_id
    join film_category on film_actor.film_id = film_category.film_id
    join category on film_category.category_id = category.category_id
    where category.name = 'Children'
    group by actor.actor_id, actor.first_name, actor.last_name
) as ranked
where 
    ranked.film_rank <= 3
order by ranked.number_of_films desc;

/*Display cities with the count of active and inactive customers 
(active = 1). Sort by the count of inactive customers in descending 
order.*/
select city.city,
  count(case when customer.active = 1 then 1 end) as active_customers,
  count(case when customer.active = 0 then 1 end) as inactive_customers
from customer 
join address on customer.address_id = address.address_id
join city on address.city_id = city.city_id
group by city.city order by inactive_customers  desc;


/*Display the film category with the highest total rental hours 
in cities where customer.address_id belongs to that city and starts 
with the letter "a". Do the same for cities containing the symbol "-". 
Write this in a single query.*/
(select category.name as category,
round(sum(extract(epoch from (rental.return_date - rental.rental_date))/3600),0) as rental_hours,
'City starts with a' as filter_type
from category
join film_category on category.category_id = film_category.category_id
join inventory on film_category.film_id = inventory.film_id
join rental on inventory.inventory_id = rental.inventory_id
join customer on rental.customer_id = customer.customer_id
join address on customer.address_id = address.address_id
join city on address.city_id = city.city_id
where city.city like 'a%' 
group by category
order by rental_hours desc
limit 1)
union all
(select category.name as category,
round(sum(extract(epoch from (rental.return_date - rental.rental_date))/3600),0) as rental_hours,
'City contains -' as filter_type
from category
join film_category on category.category_id = film_category.category_id
join inventory on film_category.film_id = inventory.film_id
join rental on inventory.inventory_id = rental.inventory_id
join customer on rental.customer_id = customer.customer_id
join address on customer.address_id = address.address_id
join city on address.city_id = city.city_id
where city.city like '%-%' 
group by category
order by rental_hours desc
limit 1);




