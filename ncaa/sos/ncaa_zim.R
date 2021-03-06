sink("diagnostics/ncaa_zim.txt")

library(glmmADMB)
library(RPostgreSQL)

drv <- dbDriver("PostgreSQL")

con <- dbConnect(drv,host="localhost",port="5432",dbname="baseball")

query <- dbSendQuery(con, "
select
r.game_id,
r.year,
r.park_id as park,
r.field as field,
r.school_id as school,
r.school_div_id as h_div,
--extract(dow from r.game_date) as dow,
--(case when extract(dow from r.game_date) in (5,6) then 'fs'
--      else 'else' end) as day,
--dt.div_id as h_div,
r.opponent_id as opponent,
r.opponent_div_id as p_div,
--dp.div_id as p_div,
r.school_score as rs
--count(*) as n
from ncaa.results r
--join ncaa.divisions dt
--  on (dt.school_name)=(r.school_name)
--join ncaa.divisions dp
--  on (dp.school_name)=(r.opponent_name)
where
    r.year between 2013 and 2015
and r.school_div_id is not null
and r.opponent_div_id is not null
and r.school_score>=0
and r.opponent_score>=0
and not(r.school_score,r.opponent_score)=(0,0)
and r.school_div_id in (1)
and r.opponent_div_id in (1)
--group by year,park,field,school,opponent,h_div,p_div,dow,day
--order by year,park,field,school,opponent,h_div,p_div
;")

games <- fetch(query,n=-1)
dim(games)

attach(games)

pll <- list()

# Fixed parameters

year <- as.factor(year)
field <- as.factor(field)
p_div <- as.factor(p_div)
h_div <- as.factor(h_div)

fp <- data.frame(year,field,p_div,h_div)
fpn <- names(fp)

# Random parameters

park <- as.factor(park)
offense <- as.factor(paste(year,"/",school,sep=""))
defense <- as.factor(paste(year,"/",opponent,sep=""))
game_id <- as.factor(game_id)

rp <- data.frame(park,offense,defense)
rpn <- names(rp)

for (n in fpn) {
  df <- fp[[n]]
  level <- as.matrix(attributes(df)$levels)
  parameter <- rep(n,nrow(level))
  type <- rep("fixed",nrow(level))
  pll <- c(pll,list(data.frame(parameter,type,level)))
}

for (n in rpn) {
  df <- rp[[n]]
  level <- as.matrix(attributes(df)$levels)
  parameter <- rep(n,nrow(level))
  type <- rep("random",nrow(level))
  pll <- c(pll,list(data.frame(parameter,type,level)))
}

# Model parameters

parameter_levels <- as.data.frame(do.call("rbind",pll))
dbWriteTable(con,c("ncaa","_zim_parameter_levels"),parameter_levels,row.names=TRUE)

g <- cbind(fp,rp)

dim(g)

#model <- rs ~ year+field+h_div+p_div+(1|park)+(1|offense)+(1|defense)
model <- rs ~ year+field+(1|park)+(1|offense)+(1|defense)
fit <- glmmadmb(model, data=g, zeroInflation=TRUE, family="nbinom", verbose=TRUE, extra.args="-ndi 120000 -rs")

fit
summary(fit)
#anova(fit)

#overdisp_fun <- function(model) {
  ## number of variance parameters in 
  ##   an n-by-n variance-covariance matrix
#  vpars <- function(m) {
#    nrow(m)*(nrow(m)+1)/2
#  }
#  model.df <- sum(sapply(VarCorr(model),vpars))+length(fixef(model))
#  rdf <- nrow(model.frame(model))-model.df
#  rp <- residuals(model,type="pearson")
#  Pearson.chisq <- sum(rp^2)
#  prat <- Pearson.chisq/rdf
#  pval <- pchisq(Pearson.chisq, df=rdf, lower.tail=FALSE)
#  c(chisq=Pearson.chisq,ratio=prat,rdf=rdf,p=pval)
#}

#overdisp_fun(fit)

# List of data frames

# Fixed factors

f <- fixef(fit)
fn <- names(f)
#fn <- names(sapply(f,names))

# Random factors

r <- ranef(fit)
rn <- names(r) 
#rn <- names(sapply(r,names)) 

results <- list()

for (n in fn) {

  df <- f[[n]]

  factor <- n
  level <- n
  type <- "fixed"
  estimate <- df

  results <- c(results,list(data.frame(factor,type,level,estimate)))

 }

for (n in rn) {

  df <- r[[n]]

  factor <- rep(n,nrow(df))
  type <- rep("random",nrow(df))
  level <- row.names(df)
  estimate <- df[,1]

  results <- c(results,list(data.frame(factor,type,level,estimate)))

 }

combined <- as.data.frame(do.call("rbind",results))

dbWriteTable(con,c("ncaa","_zim_basic_factors"),as.data.frame(combined),row.names=TRUE)

quit("no")
