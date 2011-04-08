#!/usr/bin/python
#-*- coding: utf8 -*-

"""/*********************************************************************
error code offset:
the error name space from -30,100 to -30,299.
*********************************************************************/ """
ob_iternoeud_CerOff	= -30100
ob_flux_CerOff		= -30120
ob_chemin_CerOff	= -30140
ob_point_CerOff 		= -30160
ob_nom_CerOff		= -30180
ob_dbe_CerOff		= -30200
ob_fct_CerOff		= -30220
ob_balance_CerOff	= -30230
"""Berkeleydb [db.h]	the error name space from -30,800 to -30,999.
"""
psql = {
ob_iternoeud_CerOff-1 : "ob_iternoeud_CerSPI_execute_plan"
,ob_iternoeud_CerOff-2 : "ob_iternoeud_CerBinValue"

,ob_balance_CerOff-1 : "ob_balance_CerSPI_execute_plan"
,ob_balance_CerOff-2 : "ob_balance_CerBinValue"

,ob_chemin_CerOff-1 : "ob_chemin_CerMalloc"
,ob_chemin_CerOff-2 : "ob_chemin_CerPointIncoherent"
,ob_chemin_CerOff-3 : "ob_chemin_CerParcoursAvant"
,ob_chemin_CerOff-4 : "ob_chemin_CerLoopOnOffer"
,ob_chemin_CerOff-5 : "ob_chemin_CerStockEmpty"
,ob_chemin_CerOff-6 : "ob_chemin_CerNoDraft"
,ob_chemin_CerOff-7 : "ob_chemin_CerIterNoeudErr"

,ob_dbe_CerOff-1 : "ob_dbe_CerInit"
,ob_dbe_CerOff-2 : "ob_dbe_CenvUndefined"
,ob_dbe_CerOff-3 : "ob_dbe_CerMalloc"
,ob_dbe_CerOff-4 : "ob_dbe_CerPrivUndefined"
,ob_dbe_CerOff-5 : "ob_dbe_CerStr"
,ob_dbe_CerOff-6 : "ob_dbe_CerDirErr"

,ob_fct_CerOff-1 : "ob_fct_CerStockNotFoundInA"
,ob_fct_CerOff-2 : "ob_fct_CerNotDraft"
,ob_fct_CerOff-6 : "ob_fct_CerAccordNotFound"

,ob_flux_CerOff-1 : "ob_flux_CerCheminTropLong"
,ob_flux_CerOff-2 : "ob_flux_CerCheminTropStock"
,ob_flux_CerOff-3 : "ob_flux_CerCheminPbOccStock"
,ob_flux_CerOff-4 : "ob_flux_CerCheminPbOccOwn"
,ob_flux_CerOff-5 : "ob_flux_CerCheminPbIndexStock"
,ob_flux_CerOff-6 : "ob_flux_CerCheminPbOwn"
,ob_flux_CerOff-7 : "ob_flux_CerCheminPbIndexOwn"
,ob_flux_CerOff-8 : "ob_flux_CerCheminPom"
,ob_flux_CerOff-9 : "ob_flux_CerCheminCuillere"
,ob_flux_CerOff-10 : "ob_flux_CerLoopOnOffer"
,ob_flux_CerOff-11 : "ob_flux_CerOmegaNeg"
,ob_flux_CerOff-12 : "ob_flux_CerNoeudNotStock"
,ob_flux_CerOff-13 : "ob_flux_CerCheminPom2"


,ob_point_CerOff-1 : "ob_point_CerMalloc"
,ob_point_CerOff-2 : "ob_point_CerStockEpuise"
,ob_point_CerOff-3 : "ob_point_CerGetPoint"
,ob_point_CerOff-4 : "ob_point_CerOffreInconsistant"
,ob_point_CerOff-5 : "ob_point_CerStockNotNeg"
,ob_point_CerOff-6 : "ob_point_CerAbort"
,ob_point_CerOff-7 : "ob_point_CerRefusXY"

,-30401 : "no candidate ob_fread_omega(nr,nf)"
,-30402 : "the quality.id was not found"
,-30403 : "the bid.id was not found"
,-30404 : "the account  was not found or not big enough or it's quality not owned by user"
,-30405 : "the quality.name was not found"
,-30406 : "omega should be >=0"
,-30407 : "the pivot was not found"
,-30408 : "the stock is not big ebough"
,-30409 : "the stock.id is not found"
,-30410 : "commit.id sequence is not 0..N"
,-30411 : "the draft is outdated"
,-30412 : "the owner.name is not found"
,-30413 : "The quality does not exist or is not owned by user"
,-30414 : "the qtt sould be >0"
,-30415 : "qttprovided is <=0"
,-30416 : "No stock of this draft is both owned by owner and of a quality owned by user"
,-30417 : "The owner is not partner of the Draft"
,-30418 : "Less than 2 commit found for the draft"
,-30419 : "The draft status is corrupted"
,-30420 : "the draft.id was not found"
,-30421 : "The owner.name does not exist"
,-30422 : "The draft has a status that does not allow the transition to this status"
,-30423 : "Abort in bid removalXXX(unused)"
,-30424 : "The stock of a quality owned by user is not found"
,-30425 : "the stock sid_dst was not found for the draft"
,-30426 : "the stock has the wrong type"
,-30427 : "the stock could not be inserted"
,-30428 : "The draft % has less than two commits"
,-30429 : "for commit % the stock % was not found"
,-30430 : "the type of the stock should be S or D and qtt > 0"
,-30431 : "The draft % has less than two commits"
,-30432 : "The quality % already exists for market"
,-30433 : "The quality % overflows"
,-30434 : "The quality % underflows"
,-30435 : "Cannot delete the draft"
,-30436 : "Cannot delete the draft"
,-30437 : "StockD % for the draft % not found"
,-30438 : "Internal Error"
}

