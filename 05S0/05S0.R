bird <- read.csv("hacking/dataset.csv")

library(tidyverse)

#enlever les na
bird.clean <- drop_na(bird)

#valeur numérique
bird.clean$feeder_count <- as.numeric(bird.clean$feeder_count)
bird.clean$thrash_can_count <- as.numeric(bird.clean$thrash_can_count)
bird.clean$raptor_presence <- as.numeric(bird.clean$raptor_presence)

#valeur facteur
bird.clean$city_id <- as.factor(bird.clean$city_id)
bird.clean$park_id <- as.factor(bird.clean$park_id)

library(Boruta)
library(randomForest)
library(sp)

set.seed(666) # Ajouter de l'aléatoire et assurer la reproductibilité

boruta.tree <- Boruta(bird_health_index~.,bird.clean, doTrace = 2) # le test

getSelectedAttributes(boruta.tree, withTentative = F) #le résultat

result.boruta <- attStats(boruta.tree) # sauver les résultats dans un objet
result.boruta # Tout est confirmé sauf trash

median<-data.frame(boruta.tree$ImpHistory)#données importantes pour rapporter les résultats, normalement, on rapporte les facteurs trouvés significatifs et le taux de réussi

plot(boruta.tree, las = 2, cex.axis = 0.7) # rouge = rejeté, bleu = ombre, vert = significatif (le plus important est dist.m, soit la distance de la meuse en mètre)

#random forest


random.bird<- randomForest(bird_health_index~ shrub_density + feeder_count +
                             park_id + city_id + raptor_presence +
                             road_density, bird.clean, importance = T) # on ajoute les facteurs trouvés significatifs  

#accuracy

set.seed(666)
train_indices <- sample(1:nrow(bird.clean), 0.7 * nrow(bird.clean))
train_data <- bird.clean[train_indices, ]
test_data <- bird.clean[-train_indices, ]

# Train a Random Forest regression model
random.bird.test<- randomForest(bird_health_index~ shrub_density + feeder_count +
                             park_id + city_id + raptor_presence +
                             road_density, train_data, importance = T)

# Make predictions on the test set
predictions <- predict(random.bird.test, test_data)

# Visualize the predicted vs actual values
ggplot(data.frame(Predicted = predictions, Actual = test_data$bird_health_index), 
       aes(x = Actual, y = Predicted)) +
  geom_point() +
  geom_abline(intercept = 0, slope = 1, color = "red", linetype = "dashed") +
  labs(x = "Actual Values", y = "Predicted Values")+
  theme_classic()

lm.bird <- lm(data=data.frame(Predicted = predictions, Actual = test_data$bird_health_index),
              Predicted~Actual)
summary(lm.bird)

# pseudor2
mean(random.bird$rsq)
#0.281368

# predictions
to_pred <- read.csv("hacking/to_predict.csv")

#valeur numérique
to_pred$feeder_count <- as.numeric(to_pred$feeder_count)
to_pred$thrash_can_count <- as.numeric(to_pred$thrash_can_count)


#valeur facteur
to_pred$city_id <- factor(to_pred$city_id,levels= levels(bird.clean$city_id))
to_pred$park_id <- factor(to_pred$park_id,levels= levels(bird.clean$park_id))
to_pred$raptor_presence <-factor(to_pred$raptor_presence, levels= levels(bird.clean$raptor_presence))

prediction.bird <- predict(random.bird, newdata = to_pred)

to_pred$bird_health_index<-prediction.bird

write.csv2(to_pred,"hacking/predit.csv")
