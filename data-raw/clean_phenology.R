rm(list =ls())
library(tidyverse)
library(lubridate)
library(sedgwickspecies)

outfile <- 'data-raw/cleaned_trait_data/clean_phenology.csv'

alias <- read_csv('data-raw/alias.csv')
pheno <- read_csv('data-raw/raw_trait_data/phenology_data.csv')
tapioca <- read_csv('data-raw/old-data/tapioca_trait_averages.csv')

pheno$date <- as.Date(pheno$date, format = '%m/%d/%y')

pheno$date <- as_date(pheno$date)

pheno$woy <- as.numeric(strftime(pheno$date, '%V'))

pheno <- 
  pheno %>% 
  mutate(present = !is.na(veg) + !is.na(flower) + !is.na(fruit) ) %>% 
  gather(stage, percent, veg:fruit) %>% 
  mutate(percent = ifelse( is.na(percent) & present, 0, percent)) %>% 
  filter( ! is.na(percent)) 

pheno_means <- 
  pheno %>%
  group_by(Species, stage, woy) %>% 
  summarise( m_date = mean(percent)) 

fruit_models <- 
  pheno_means %>% 
  filter( stage == 'fruit') %>% 
  arrange( Species, woy) %>% 
  group_by( Species, m_date) %>%
  filter(  (n() > 1 & m_date == 0 & woy == max(woy) ) | (n() > 1 & m_date == 100 & woy == max(woy) ) | (n() == 1) ) %>%
  ungroup() %>% 
  group_by(Species) %>% 
  do(model = lm(m_date ~ woy, data = .))

flower_models <- 
  pheno_means %>% 
  filter( stage == 'flower') %>% 
  arrange( Species, woy) %>% 
  group_by( Species, m_date) %>%
  filter(  (n() > 1 & m_date == 0 & woy == max(woy) ) | (n() > 1 & m_date == 100 & woy == max(woy) ) | (n() == 1) ) %>%
  ungroup() %>% 
  group_by(Species) %>% 
  do(model = lm(m_date ~ woy, data = .))

names( fruit_models[[2]]) <- fruit_models[[1]]
names( flower_models[[2]]) <- flower_models[[1]]

calc_w50 <- function(model){ 
  cffs <- model$coefficients 
  (50 - cffs[1])/cffs[2] 
}

fr50 <- lapply( fruit_models$model, calc_w50)
fl50 <- lapply( flower_models$model, calc_w50)

fr50 <- data.frame( do.call( rbind, fr50 ) )
fr50$Species <- rownames(fr50)
fr50 <- fr50 %>% rename( 'fr50' = X.Intercept.)

fl50 <- data.frame( do.call( rbind, fl50 ) )
fl50$Species <- rownames(fl50)
fl50 <- fl50 %>% rename( 'fl50' = X.Intercept.)

pheno_means %>% 
  ggplot( aes( x = woy, y = m_date, color = stage )) + 
  geom_point() + 
  geom_line()  + 
  geom_vline(data =  fr50, aes(xintercept = fr50), linetype = 2) + 
  facet_wrap( ~ Species ) + 
  scale_color_manual(values = c(1, 2, 4))

pheno_means %>% 
  ggplot( aes( x = woy, y = m_date, color = stage )) + 
  geom_point() + 
  geom_line()  + 
  geom_vline(data =  fl50, aes(xintercept = fl50), linetype = 2) + 
  facet_wrap( ~ Species ) + 
  scale_color_manual(values = c(1, 2, 4))

fr50 %>% 
  mutate( species_lab = factor( Species, levels = unique(Species[order(fr50, Species)]), ordered = T)) %>% 
  ggplot(aes(x = species_lab, y = fr50)) + 
  geom_point() + 
  coord_flip()  

fl50 %>% 
  mutate( species_lab = factor( Species, levels = unique(Species[order(fl50, Species)]), ordered = T)) %>% 
  ggplot(aes(x = species_lab, y = fl50)) + 
  geom_point() + 
  coord_flip()  

fr50 <- 
  fr50 %>% 
  mutate( doy_fr_50 = round( fr50*7) )

fr50 <- 
  left_join(fr50, sedgwick_plants %>% select(calflora_binomial, standard_binomial, USDA_symbol), 
          by = c('Species' = 'standard_binomial'))  %>% 
  select( Species, calflora_binomial, USDA_symbol, doy_fr_50) %>% 
  distinct() %>% 
  rename ('phenology (DOY 50% fruit)' = doy_fr_50) %>% 
  mutate( dataset = '2017')

tapioca <- 
  tapioca %>% 
  left_join(alias, by = c('species' = 'alias')) %>% 
  mutate( dataset = 'tapioca') %>% 
  select( USDA_symbol, `phenology (corrected May 2016- frame shift error)`, dataset) %>% 
  rename ('phenology (DOY 50% fruit)' = `phenology (corrected May 2016- frame shift error)`) 
  
average_phenology <- 
  bind_rows(fr50, tapioca) %>%   
  select( USDA_symbol, `phenology (DOY 50% fruit)`, dataset)

average_phenology %>% 
  mutate( USDA_symbol = factor( USDA_symbol, levels = unique(USDA_symbol[order(`phenology (DOY 50% fruit)`)]), ordered = T)) %>% 
  ggplot(aes(x = USDA_symbol, y = `phenology (DOY 50% fruit)`, color = dataset)) + 
  geom_point() + 
  coord_flip()  

write_csv(average_phenology, outfile)
