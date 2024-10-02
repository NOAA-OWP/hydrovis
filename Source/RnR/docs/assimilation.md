# Assimilation

Based on the PWS requirements (2.3.4.1.4) we must assimilat forecasts that have flooding. 

```
Assimilate RFC forecasts that have values within the forecast horizon that are at or above
flood stage as defined by the local NWS field offices. RFC forecasts shall be assimilated
upstream of the RFC forecast location at a distance greater than 2 miles, but not to exceed 5
miles
```

To account for this, we are inserting flow using the upstream catchment of the RFC point using enterprise hydrofabric connectivity. Since there is a many to one relationship between catchments to nexus points, we just have to use the direct catchment upstream. 

Below is a photo of the assimilation in action. The grey catchments are areas where there is no flow, and the green catchments are areas where there is flow. 

![alt text](photos/assimilation.png)
