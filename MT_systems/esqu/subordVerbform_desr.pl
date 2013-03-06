#!/usr/bin/perl


use utf8;                  # Source code is UTF-8
use open ':utf8';
use Storable; # to retrieve hash from disk
binmode STDIN, ':utf8';
#binmode STDOUT, ':utf8';
use strict;
use XML::LibXML;
use File::Spec::Functions qw(rel2abs);
use File::Basename;
my $path = dirname(rel2abs($0));
require "$path/../util.pl";

#read xml from STDIN
my $parser = XML::LibXML->new({encoding => 'utf-8'});
my $dom    = XML::LibXML->load_xml( IO => *STDIN);

my @sentenceList = $dom->getElementsByTagName('SENTENCE');

# note that if the subordinated clause preceeds the main clause, subordination depends on main verb:
#  <SENTENCE ord="1">
#    <CHUNK type="grup-verb" si="top" ord="6">
#      <NODE ord="6" form="saldré" lem="salir" pos="vm" cpos="v" rel="sentence" mi="VMIF1S0">
#        <NODE ord="1" form="Cuando" lem="cuando" pos="cs" cpos="c" head="6" rel="conj" mi="CS"/>
#      </NODE>
#      <CHUNK type="grup-verb" si="suj" ord="2">
#        <NODE ord="2" form="termino" lem="terminar" pos="vm" cpos="v" rel="suj" mi="VMIP1S0"/>
#        <CHUNK type="grup-sp" si="creg" ord="3">
#          <NODE ord="3" form="de" lem="de" pos="sp" cpos="s" rel="creg" mi="SPS00"/>
#          <CHUNK type="grup-verb" si="S" ord="4">
#            <NODE ord="4" form="comer" lem="comer" pos="vm" cpos="v" rel="S" mi="VMN0000"/>
#          </CHUNK>
#        </CHUNK>
#        <CHUNK type="F-term" si="term" ord="5">
#          <NODE ord="5" form="," lem="," pos="Fc" cpos="F" mi="FC"/>
#        </CHUNK>
#      </CHUNK>
#      <CHUNK type="F-term" si="term" ord="7">
#        <NODE ord="7" form="." lem="." pos="Fp" cpos="F" mi="FP"/>
#      </CHUNK>
#    </CHUNK>
#  </SENTENCE>


my $nbrOfRelClauses =0;
my $nbrOfSwitchForms=0;
my $nbrOfComplementClauses=0;
my $nbrOfFinalClauses=0;
my $nbrOfMainClauses=0;
my $nbrOfAmbigousClauses=0;
my $nbrOfVerbChunks=0;
my $nbrOfNonFiniteChunks=0;

foreach my $sentence (@sentenceList)
{
	# get all verb chunks and check if they have an overt subject, 
	# if they don't have an overt subject and precede the main clause -> look for subject in preceding sentence
	# if they don't have an overt subject and follow the main clause, and the main clause has an overt subject, this is the subject of the subordinated chunk
	print STDERR "Disambiguating verb form in sentence:";
	print STDERR $sentence->getAttribute('ord')."\n";
	
 	
 	# consider linear sequence in sentence; in xml the verb of the main clause comes always first, but in this case the subject of a preceding subordinated clause is probably coreferent with the subject of the preceding clause
 	my @verbChunks = $sentence->findnodes('descendant::CHUNK[@type="grup-verb" or @type="coor-v"]');
 	$nbrOfVerbChunks = $nbrOfVerbChunks+scalar(@verbChunks);
 	#print STDERR "$nbrOfVerbChunks\n";
 	
 	foreach my $verbChunk (@verbChunks)
 	{
 		if(&getFiniteVerb($verbChunk))
 		{
 			# disambiguation needed only if not relative clause (those are handled separately)
 			if( !&isRelClause($verbChunk) )
 			{
 				# if this verb has a 'tener que' part -> obligative, TODO: hay que?
 				if($verbChunk->exists('child::NODE[@cpos="v"]/NODE[@lem="tener"]/NODE[@lem="que" and @pos="cs"]') || ($verbChunk->exists('child::NODE[@mi="VMN0000"]/NODE[@lem="tener"]') && $verbChunk->exists('child::NODE[@mi="VMN0000"]/NODE[@lem="que"]') ))
 				{
 					$nbrOfFinalClauses++;
 					$verbChunk->setAttribute('verbform', 'obligative');
 				}
 				# if this is a subordinated clause with 'si/cuando..'-> switch-reference forms (desr sometimes makes the sub-clause the main clause)
 				elsif( $verbChunk->exists('child::NODE[@cpos="v"]/NODE[@lem="si" or @lem="cuando" or @lem="mientras_que"]') || $verbChunk->exists('parent::CHUNK[@type="coor-v"]/NODE[@cpos="v"]/NODE[@lem="si" or @lem="cuando"]') )
 				{
 					#check if same subject 
 					&compareSubjects($verbChunk);
 				}
 				# if this is a main clause, or a coordinated verbform of a main clause, set verform to 'main'
 				elsif( ($verbChunk->exists('self::CHUNK[@si="top"]') ||  $verbChunk->exists('parent::CHUNK[@si="top" and @type="coor-v"]')) && !$verbChunk->exists('child::NODE[@cpos="v"]/NODE[@pos="cs"]') )
 				{
 					$nbrOfMainClauses++;
 					$verbChunk->setAttribute('verbform', 'main');
 				}
 				# if subordinated clause is a gerund -> set to spa-form (trabaja cantando)
 				elsif($verbChunk->exists('child::NODE[starts-with(@mi, "VMG")]') && !$verbChunk->exists('descendant::NODE[@pos="va" or @pos="vs"]') && !$verbChunk->exists('child::NODE[starts-with(@mi, "VMG")]/NODE[@lem="venir" or @lem="ir" or @lem="andar" or @lem="estar"]')  )
 				{
 					$nbrOfSwitchForms++;
 					$verbChunk->setAttribute('verbform', 'SS');
 				}
 				# if this is a complement clause (-> nominal form), TODO: already ++Acc?
 				elsif($verbChunk->exists('self::CHUNK[@si="sentence" or @si="cd" or @si="CONCAT"]/NODE/NODE[@pos="cs"]') && $verbChunk->exists('parent::CHUNK[@type="grup-verb"]')) 
 				{
 					$nbrOfComplementClauses++;
 					if(&isSubjunctive($verbChunk) or &isFuture($verbChunk))
 					{
 						$verbChunk->setAttribute('verbform', 'obligative');
 					}
 					else
 					{
 						$verbChunk->setAttribute('verbform', 'perfect');
 					}
 				}
				# if this is a final clause,  -na?
				elsif($verbChunk->exists('child::NODE[@cpos="v"]/NODE[@lem="para_que" or @lem="con_fin_de_que"]') && &isSubjunctive($verbChunk))
				{
					$nbrOfFinalClauses++;
					$verbChunk->setAttribute('verbform', 'obligative');
				}
				else
				{
					$nbrOfAmbigousClauses++;
					$verbChunk->setAttribute('verbform', 'ambiguous');
				}
 			}
			else
			{
				$nbrOfRelClauses++;
			}
 		}
 		else
 		{
 			$nbrOfNonFiniteChunks++;
 		}
 	}
}

print STDERR "\n****************************************************************************************\n";
print STDERR "total number of verb chunks: ".$nbrOfVerbChunks."\n";
print STDERR "total number of verb chunks with no finite verb: ".$nbrOfNonFiniteChunks."\n";
print STDERR "total number of relative clauses: $nbrOfRelClauses \n";
print STDERR "total number of switch reference forms: ".$nbrOfSwitchForms."\n";
print STDERR "total number of complement clauses: ".$nbrOfComplementClauses."\n";
print STDERR "total number of final clauses: ".$nbrOfFinalClauses."\n";
print STDERR "total number of main clauses: ".$nbrOfMainClauses."\n";
print STDERR "total number of ambiguous clauses: ".$nbrOfAmbigousClauses."\n";
print STDERR "total number of disambiguated verb forms: ".($nbrOfRelClauses+$nbrOfSwitchForms+$nbrOfComplementClauses+$nbrOfFinalClauses+$nbrOfMainClauses)."\n";
print STDERR "\n****************************************************************************************\n";

# print new xml to stdout
my $docstring = $dom->toString(1);
#print STDERR $dom->actualEncoding();
print STDOUT $docstring;

sub compareSubjects{
	my $verbChunk = $_[0];
	my $finiteVerb = &getFiniteVerb($verbChunk);
	print STDERR "compare subjs in chunk:".$verbChunk->getAttribute('ord')."\n";
	#subject of main clause
	my $mainverb = &getVerbMainClause($verbChunk);
	if($mainverb && $finiteVerb)
	{
		my $finiteMainVerb = &getFiniteVerb($mainverb);
		#print STDERR $finiteMainVerb->toString;
		#compare person & number
		if($finiteMainVerb  && $finiteVerb->getAttribute('mi') =~ /1|2/ )
		{
			my $verbMI = $finiteVerb->getAttribute('mi');
			my $verbPerson = substr ($verbMI, 4, 1);
			my $verbNumber = substr ($verbMI, 5, 1);
	
			my $verbMIMain = $finiteMainVerb->getAttribute('mi');
			my $verbPersonMain = substr ($verbMIMain, 4, 1);
			my $verbNumberMain = substr ($verbMIMain, 5, 1);
		
			#print STDERR $finiteMainVerb ->getAttribute('lem').": $verbMIMain\n";
			#print STDERR $finiteVerb->getAttribute('lem').": $verbMI\n";
		
			if($verbPerson eq $verbPersonMain && $verbNumber eq $verbNumberMain)
			{
				$nbrOfSwitchForms++;
				$verbChunk->setAttribute('verbform', 'SS');
			}
			else
			{
				$nbrOfSwitchForms++;
				$verbChunk->setAttribute('verbform', 'DS');
			}
		}
		# if 3rd person
		elsif($finiteMainVerb  && $finiteVerb->getAttribute('mi') !~ /1|2/ )
		{ 
		 	 # if main verb SAP -> DS
		  	 if($finiteMainVerb->getAttribute('mi') =~ /1|2/)
		 	 {
		 	 		$nbrOfSwitchForms++;
		  			$verbChunk->setAttribute('verbform', 'DS');
		 	 }
		 	 else
		 	 {
		  		#check number
		  		my $verbNumberMain = substr ($finiteMainVerb->getAttribute('mi'), 5, 1);
		  		my $verbNumber = substr ($finiteVerb->getAttribute('mi'), 5, 1);
		  	
		 	 	#print STDERR $finiteMainVerb ->getAttribute('lem').": ".$finiteMainVerb->getAttribute('mi')."\n";
				#print STDERR $finiteVerb->getAttribute('lem').": ".$finiteVerb->getAttribute('mi')."\n";
		  	
			  	if($verbNumber ne $verbNumberMain)
			  	{
			  		$nbrOfSwitchForms++;
		  			$verbChunk->setAttribute('verbform', 'DS');
		  		}
		  		# else, if both 3rd and same number: check coref
		  		else
		  		{
					# subject of this (subordinate) clause
					my ($subjNoun, $subjMI ) = &getSubjectNoun($verbChunk);
					my ($subjNounMain,$subjMIMain ) =  &getSubjectNoun($mainverb);
		
				#if subjects of main and subord clause found, check if they're the same
				if($subjNounMain,$subjNoun,$subjMIMain,$subjMI)
				{
					if($subjNounMain eq $subjNoun && $subjMIMain eq $subjMI)
					{
						$nbrOfSwitchForms++;
						$verbChunk->setAttribute('verbform', 'SS');
					}
					else
					{
						$nbrOfSwitchForms++;
						$verbChunk->setAttribute('verbform', 'DS');
					}
				}
				else
				{
					$nbrOfAmbigousClauses++;
					$verbChunk->setAttribute('verbform', 'ambiguous'); # maybe better default=DS here?
				}
			}
		  	}
		}
	}
	 # if no main verb found, set verbform to ambiguous
	else
	{
		$nbrOfAmbigousClauses++;
		$verbChunk->setAttribute('verbform', 'ambiguous');
	}
}

sub isSubjunctive{
	my $verbChunk = $_[0];
	my $finiteVerb = &getFiniteVerb($verbChunk);
	if($finiteVerb)
	{
		return substr($finiteVerb->getAttribute('mi'), 2, 1) eq 'S';
	}
	else
	{
		return 0;
	}
}

sub isFuture{
	my $verbChunk = $_[0];
	my $finiteVerb = &getFiniteVerb($verbChunk);
	if($finiteVerb)
	{
		return substr($finiteVerb->getAttribute('mi'), 3, 1) eq 'F';
	}
	else
	{
		return 0;
	}
}

sub getSubjectNoun{
	my $verbChunk = $_[0];
	my ($subjectNoun,$subjectNounMI);
	my $subjectChunk = @{$verbChunk->findnodes('child::CHUNK[@si="subj" or @si="subj-a"][1]')}[-1];
	
	if($subjectChunk)
	{
			$subjectNoun = $subjectChunk->findvalue('NODE[@cpos="n" or @pos="pp"][1]/@lem');
			$subjectNounMI = $subjectChunk->findvalue('NODE[@cpos="n" or @pos="pp"][1]/@mi');
	}
	# else if no overt subject, but coref
	elsif($verbChunk->exists('self::CHUNK/@coref'))
	{
		$subjectNoun = $verbChunk->getAttribute('coref');
		$subjectNounMI = $verbChunk->getAttribute('corefmi');
	}
	else
	{
		print STDERR "no subject, no coref in: ";
		#print STDERR $verbChunk->toString;
		print STDERR "\n";
	}

	my @subj = ($subjectNoun, $subjectNounMI);
	print STDERR "$subjectNoun:$subjectNounMI\n";
	return @subj;
}


sub getVerbMainClause{
	my $subordVerbChunk= $_[0];
	my $headVerbChunk; 
	
	#if this subordinated clause is wrongly analysed as main clause
	if($subordVerbChunk && $subordVerbChunk->exists('self::CHUNK[@si="top"]'))
	{
		#print STDERR "subord verb chunk: ".$subordVerbChunk->toString()."\n";
		$headVerbChunk = @{$subordVerbChunk->findnodes('child::CHUNK[@type="grup-verb" or @type="coor-v"][1]')}[0];
	}
	elsif($subordVerbChunk && $subordVerbChunk->exists('ancestor::SENTENCE/CHUNK[@si="top" and @type="grup-verb"]'))
	{
		$headVerbChunk = @{$subordVerbChunk->findnodes('ancestor::SENTENCE/CHUNK[@si="top" and @type="grup-verb"][1]')}[0];
	}
	# if head of sentence is not a verb chunk -> wrong analysis or incomplete sentence (e.g. title)
	# -> check if subord verb chunk has any verb chunks as ancestor
	elsif($subordVerbChunk && $subordVerbChunk->exists('ancestor::SENTENCE/CHUNK[@si="top" and not(@type="grup-verb")]') )
	{
		$headVerbChunk = @{$subordVerbChunk->findnodes('ancestor::CHUNK[@type="grup-verb"][1]')}[0];
	}
	else
	{
		#get sentence id
		my $sentenceID = $subordVerbChunk->findvalue('ancestor::SENTENCE/@ord');
		print STDERR "head verb chunk not found in sentence nr. $sentenceID: \n ";
		print $subordVerbChunk->toString();
		print "\n";
		return 0;
	}
	return $headVerbChunk;
}