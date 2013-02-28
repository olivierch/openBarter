openBarter
==========

openBarter is a postgreSQL extension defining a barter market of fungible. It implements the economic mechanisms of a regular market ( central limit order book) and allows cyclic exchanges between more than two partners (buyer and seller) in a single transaction. Barter orders are used by owners to provide a quality in exchange of an other. The ratio beween the quatity provided and the quantity required expresses as a price the will to exchange. This ratio is used by openBarter to implement a competition between possible exchange cycles. It does not any central monetary standard to do it. By multilateral cycles, it provides a good liquidity when the diversity of qualities is not too large.

Content
-------

* /doc documentation. 
* /src contains sources files, and the Makefile. the make command should be run into this directory.
* LICENCE.txt
* openbarter.control and META.json files required by PGXN manager. 


