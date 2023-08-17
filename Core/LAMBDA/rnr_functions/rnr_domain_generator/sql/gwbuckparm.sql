SELECT 
    NULL as "Area_sqkm",
    row_number() over (ORDER BY order_index) as "Basin",
    rl.link as "ComID",
    NULL as "Expon",
    10.0 as "Zinit",
    NULL as "Zmax",
    1.0 as "Coeff"
FROM rnr.domain_routelink rl
ORDER BY order_index;