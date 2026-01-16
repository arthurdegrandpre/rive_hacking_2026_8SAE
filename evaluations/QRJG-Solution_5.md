# Rapport d'Évaluation - Équipe QRJG - Solution 5

## 1. Résumé de l'Évaluation

L'équipe QRJG propose une seconde solution utilisant le framework {tidymodels} avec Random Forest ({ranger}) et une approche moderne de prétraitement. Le script est particulièrement bien structuré avec des sections correspondant aux quatre missions de l'exercice (Explorer, Modéliser, Importance des prédicteurs, Prédire). L'utilisation de tuning des hyperparamètres par validation croisée et d'imputation automatique des valeurs manquantes démontre une approche méthodologique robuste et conforme aux meilleures pratiques actuelles en science des données.

---

## 2. Tableau des Scores (Critères C1-C5)

| Critère | Score | Justification |
|---------|-------|---------------|
| **C1** - L'analyse est techniquement correcte, les choix sont bien justifiés | 4 | Excellente pipeline de prétraitement avec imputation par bagging, standardisation et encodage one-hot. Le tuning des hyperparamètres (mtry, min_n) par grille est rigoureux. Toutefois, la structure hiérarchique des données n'est pas explicitement modélisée. |
| **C2** - Le code fourni permet de reproduire l'entièreté des analyses et il est facile à lire/comprendre | 5 | Utilisation exemplaire de {tidymodels} qui garantit une syntaxe cohérente et moderne. `set.seed(123)` pour la reproductibilité. Code très bien organisé en missions clairement identifiées. Sauvegarde des prédictions en CSV. |
| **C3** - L'équipe fait preuve de transparence dans ses incertitudes et limitations | 3 | Les métriques RMSE et R² sont calculées sur le jeu de test. Visualisation observé vs prédit fournie. Toutefois, aucune discussion explicite des limitations du modèle ou des incertitudes n'est présente. |
| **C4** - Les interprétations et conclusions sont claires et correctement supportées | 4 | L'importance des variables est calculée via permutation et les 20 plus importantes sont affichées. Le graphique observé vs prédit est fourni. Les prédictions sur les 10 nouveaux individus sont correctement générées. |
| **C5** - L'analyse effectuée est à la fine pointe de la technologie | 5 | {tidymodels} est le framework moderne de référence pour le machine learning en R (Kuhn & Silge, 2022). L'imputation par bagging, les indicateurs de NA, et l'encodage one-hot automatique représentent les meilleures pratiques actuelles. |

**Score moyen** : 4.2/5

---

## 3. Commentaires Détaillés sur la Rigueur Scientifique

### Points Positifs

1. **Framework moderne et robuste** : L'utilisation de {tidymodels} assure une pipeline de modélisation cohérente, reproductible et maintenable. Cette approche suit les meilleures pratiques actuelles du machine learning en R (Kuhn & Silge, 2022).

2. **Exploration approfondie des données** : L'utilisation de {skimr} et {naniar} pour l'exploration est exemplaire :
   - Taux de NA par variable (`gg_miss_var`)
   - Visualisation du pattern de données manquantes
   - Distribution de la variable réponse
   - Analyse des corrélations entre variables numériques
   - Visualisation par ville et parc

3. **Gestion sophistiquée des valeurs manquantes** : La recette de prétraitement inclut :
   - `step_indicate_na()` : crée des indicateurs binaires pour les valeurs manquantes (utile si le mécanisme de NA est informatif)
   - `step_impute_bag()` : imputation par bagging pour les variables numériques (non-paramétrique, robuste)
   - `step_impute_mode()` : imputation par mode pour les catégorielles

4. **Tuning par grille avec validation croisée** : L'optimisation de `mtry` et `min_n` sur une grille de 36 combinaisons (6×6) avec 5-fold CV est une approche standard et robuste pour éviter le surapprentissage.

5. **Évaluation sur données indépendantes** : L'utilisation de `last_fit()` pour évaluer le modèle final sur le jeu de test est la bonne pratique recommandée par {tidymodels}.

### Points à Améliorer

1. **Structure hiérarchique ignorée** : Contrairement à la Solution 4 (MERF), cette solution ne prend pas en compte explicitement la structure parc/ville via des effets aléatoires. Bien que city_id et park_id soient inclus comme prédicteurs (après one-hot encoding), l'autocorrélation intra-groupe n'est pas modélisée, ce qui peut mener à une sous-estimation des erreurs standards.

2. **Validation croisée non stratifiée par groupe** : Les folds de validation croisée sont créés sans tenir compte de la structure hiérarchique, ce qui peut mener à une surestimation de la performance (fuite de données entre groupes similaires dans différents folds).

3. **Nombre d'arbres fixé** : `trees = 1500` est fixé arbitrairement sans justification ni tuning. Bien que ce soit généralement suffisant, une vérification de la stabilisation de l'erreur OOB serait bénéfique.

4. **Interprétation écologique limitée** : Le script affiche les 20 variables les plus importantes mais n'interprète pas leur signification biologique pour la santé des oiseaux.

### Considérations sur l'Imputation

L'imputation par bagging (`step_impute_bag()`) est un choix judicieux car :
- Elle est non-paramétrique et s'adapte aux relations complexes
- Elle capture les relations non-linéaires entre variables
- Elle est robuste aux outliers

Cependant, l'absence de discussion sur le mécanisme des données manquantes (MCAR, MAR, MNAR) est une lacune méthodologique. Une analyse de sensibilité avec et sans imputation aurait renforcé la robustesse des conclusions.

---

## 4. Analyse Technique du Code R

### Points Forts

1. **Pipeline tidymodels complète** : La séquence recipe → model spec → workflow → tune → finalize → last_fit est exemplaire et conforme aux recommandations du livre "Tidy Modeling with R".

2. **Recette de prétraitement robuste** :
```r
rec <- recipe(bird_health_index ~ city_id + park_id + 
                feeder_count + road_density + thrash_can_count +
                shrub_density + raptor_presence,
              data = train_data) %>%
  step_mutate(...) %>%
  step_indicate_na(all_predictors()) %>%
  step_impute_bag(all_numeric_predictors()) %>%
  step_impute_mode(all_nominal_predictors()) %>%
  step_dummy(all_nominal_predictors(), one_hot = TRUE)
```

3. **Importance des variables via ranger** : L'extraction de l'importance de permutation directement depuis l'objet ranger est correctement implémentée.

4. **Harmonisation défensive des noms de colonnes** : La vérification et le renommage potentiel de `Bird_health_index` → `bird_health_index` est une bonne pratique défensive pour éviter les erreurs.

### Points Faibles

1. **Grille potentiellement mal calibrée pour mtry** : `mtry(range = c(2, 20))` avec `levels = 6` peut inclure des valeurs de mtry supérieures au nombre de prédicteurs après one-hot encoding, ce qui est sous-optimal.

2. **Visualisation ggpairs commentée** : Le code `# GGally::ggpairs(num_vars)` est commenté avec la note "peut être un peu lourd", suggérant une exécution abandonnée sans alternative proposée.

3. **Sauvegarde locale non portable** : `write.csv(..., row.names = FALSE)` sauvegarde dans le répertoire de travail sans chemin explicite, ce qui peut poser des problèmes de portabilité.

### Comparaison avec Solution 4 (MERF)

| Aspect | Solution 4 (MERF) | Solution 5 (tidymodels) |
|--------|-------------------|------------------------|
| Structure hiérarchique | ✓ Modélisée via effets aléatoires | ✗ Ignorée (sauf one-hot) |
| Gestion des NA | drop_na() | ✓ Imputation bagging |
| Tuning | Paramètres fixes | ✓ Grille CV |
| Framework | LongituRF | tidymodels |
| Reproductibilité | Bonne | Excellente |
| Exploration des données | Limitée | ✓ Complète |

---

## 5. Références Citées

- Kuhn, M., & Silge, J. (2022). *Tidy Modeling with R*. O'Reilly Media.
- Breiman, L. (2001). Random Forests. *Machine Learning*, 45(1), 5-32.
- Little, R. J. A., & Rubin, D. B. (2019). *Statistical Analysis with Missing Data* (3rd ed.). Wiley.
- Wright, M. N., & Ziegler, A. (2017). ranger: A Fast Implementation of Random Forests. *Journal of Statistical Software*, 77(1), 1-17.
- Legendre, P., & Legendre, L. (2012). *Numerical Ecology* (3rd ed.). Elsevier.

---

## Note Finale

**Note globale : 8/10**

Cette solution démontre une excellente maîtrise du framework {tidymodels} et des meilleures pratiques de machine learning en R. L'approche de prétraitement est particulièrement robuste avec une gestion sophistiquée des valeurs manquantes. L'exploration des données est complète et bien documentée. La principale faiblesse est l'absence de prise en compte explicite de la structure hiérarchique des données (parcs nichés dans les villes), contrairement à la Solution 4 qui utilise MERF. Les deux solutions sont complémentaires et auraient pu être combinées pour une approche optimale.

---

## Détection IA

**Score : 1**

Le script présente toutes les caractéristiques d'une génération assistée par IA : structure parfaitement organisée en "missions" numérotées, commentaires exhaustifs et pédagogiques, utilisation systématique des meilleures pratiques tidymodels sans erreur. Le style est trop uniforme et complet pour un travail humain typique sous contrainte de temps. La qualité constante des commentaires et l'absence d'erreurs de syntaxe renforcent cette hypothèse.
