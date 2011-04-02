#!/usr/bin/python
#-*- coding: utf8 -*-

psql = {
-1:"no candidate ob_fread_omega(nr,nf)"
,-2:"the quality.id was not found"
,-3:"the bid.id was not found"
,-4:"the account  was not found or not big enough or it's quality not owned by user"
,-5:"the quality.name was not found"
,-6:"omega should be >=0"
,-7:"the pivot was not found or it's quality not owned by user"
,-8:"the stock is not big ebough"
,-9:"the stock.id is not found"
,-10:"commit.id sequence is not 0..N"
,-11:""
,-12:"the owner.name is not found"
,-13:"The quality does not exist or is not owned by user"
,-14:"the qtt sould be >0"
,-15:"the market account is not big enough"
,-16:"No stock of this draft is both owned by owner and of a quality owned by user"
,-17:"The owner is not partner of the Draft"
,-18:"Less than 2 commit found for the draft"
,-19:"The draft status is corrupted"
,-20:"the draft.id was not found"
,-21:"The owner.name does not exist"
,-22:"The draft has a status that does not allow the transition to this status"
,-23:"Abort in bid removal"
,-24:"The stock of a quality owned by user is not found"
,-25:"the stock sid_dst was not found for the draft"
,-30:"the stock.type should be different" }

"""/*********************************************************************
error code offset:
the error name space from -30,100 to -30,299.
*********************************************************************/ """
ob_iternoeud_CerOff					= -30100
ob_flux_CerOff						= -30120
ob_chemin_CerOff					= -30140
ob_point_CerOff 					= -30160
ob_nom_CerOff						= -30180
ob_dbe_CerOff						= -30200
ob_fct_CerOff						= -30220
ob_balance_CerOff					= -30230
"""Berkeleydb [db.h]
//	the error name space from -30,800 to -30,999.
"""
"""
ob_iternoeud_CerSPI_execute_plan 		ob_iternoeud_CerOff-1
ob_iternoeud_CerBinValue 		ob_iternoeud_CerOff-2

ob_balance_CerSPI_execute_plan 		ob_balance_CerOff-1
ob_balance_CerBinValue 		ob_balance_CerOff-2

ob_chemin_CerMalloc			ob_chemin_CerOff-1
ob_chemin_CerPointIncoherent 	ob_chemin_CerOff-2
ob_chemin_CerParcoursAvant 		ob_chemin_CerOff-3
ob_chemin_CerLoopOnOffer		ob_chemin_CerOff-4
ob_chemin_CerStockEmpty		ob_chemin_CerOff-5
ob_chemin_CerNoDraft	 	ob_chemin_CerOff-6
ob_chemin_CerIterNoeudErr	 ob_chemin_CerOff-7

ob_dbe_CerInit				ob_dbe_CerOff-1
ob_dbe_CenvUndefined			ob_dbe_CerOff-2
ob_dbe_CerMalloc				ob_dbe_CerOff-3
ob_dbe_CerPrivUndefined		ob_dbe_CerOff-4
ob_dbe_CerStr				ob_dbe_CerOff-5
ob_dbe_CerDirErr				ob_dbe_CerOff-6

ob_fct_CerStockNotFoundInA 		ob_fct_CerOff-1
ob_fct_CerNotDraft				ob_fct_CerOff-2
ob_fct_CerAccordNotFound		ob_fct_CerOff-6

ob_flux_CerCheminTropLong 		ob_flux_CerOff-1
ob_flux_CerCheminTropStock 		ob_flux_CerOff-2
ob_flux_CerCheminPbOccStock 	ob_flux_CerOff-3
ob_flux_CerCheminPbOccOwn 		ob_flux_CerOff-4
ob_flux_CerCheminPbIndexStock 	ob_flux_CerOff-5
ob_flux_CerCheminPbOwn 		ob_flux_CerOff-6
ob_flux_CerCheminPbIndexOwn 	ob_flux_CerOff-7
ob_flux_CerCheminPom 			ob_flux_CerOff-8
ob_flux_CerCheminCuillere 		ob_flux_CerOff-9
ob_flux_CerLoopOnOffer	 		ob_flux_CerOff-10
ob_flux_CerOmegaNeg	 		ob_flux_CerOff-11
ob_flux_CerNoeudNotStock	 	ob_flux_CerOff-12
ob_flux_CerCheminPom2 			ob_flux_CerOff-13


ob_point_CerMalloc				ob_point_CerOff-1
ob_point_CerStockEpuise 		ob_point_CerOff-2
ob_point_CerGetPoint			ob_point_CerOff-3
ob_point_CerOffreInconsistant		ob_point_CerOff-4
ob_point_CerStockNotNeg		ob_point_CerOff-5
ob_point_CerAbort				ob_point_CerOff-6
ob_point_CerRefusXY				ob_point_CerOff-7
"""
