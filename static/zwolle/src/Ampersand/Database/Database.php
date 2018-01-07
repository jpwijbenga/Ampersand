<?php

/*
 * This file is part of the Ampersand backend framework.
 *
 */

namespace Ampersand\Database;
use mysqli;
use DateTime;
use Exception;
use DateTimeZone;
use Ampersand\Misc\Config;
use Ampersand\Session;
use Ampersand\Core\Atom;
use Ampersand\Core\Link;
use Ampersand\Core\Concept;
use Ampersand\Core\Relation;
use Ampersand\Interfacing\ViewSegment;
use Ampersand\Interfacing\InterfaceObject;
use Ampersand\Plugs\ConceptPlugInterface;
use Ampersand\Plugs\IfcPlugInterface;
use Ampersand\Plugs\RelationPlugInterface;
use Ampersand\Plugs\ViewPlugInterface;
use Ampersand\Transaction;
use Ampersand\Log\Logger;
use Ampersand\Rule\Conjunct;

/**
 *
 * @author Michiel Stornebrink (https://github.com/Michiel-s)
 *
 */
class Database implements ConceptPlugInterface, RelationPlugInterface, IfcPlugInterface, ViewPlugInterface {
    /**
     * Logger
     * 
     * @var \Psr\Log\LoggerInterface
     */
    private $logger;
    
    /**
     * A connection to the mysql database
     * 
     */
    protected $dbLink;
    
    /**
     * Host/server of mysql database
     * 
     * @var string
     */
    protected $dbHost;
    
    /**
     * Username for mysql database
     * 
     * @var string
     */
    protected $dbUser;
    
    /**
     * Password for mysql database
     * 
     * @var string
     */
    protected $dbPass;
    
    /**
     * Database name
     * 
     * @var string
     */
    protected $dbName;
    
    /**
     * Specifies if database transaction is active
     * 
     * @var bool
     */
    protected $dbTransactionActive = false;

    /**
     * Contains the last executed query
     *
     * @var $string
     */
    protected $lastQuery = null;
    
    /**
     * Constructor of database class
     * 
     */
    public function __construct($dbHost, $dbUser, $dbPass, $dbName){
        $this->logger = Logger::getLogger('DATABASE');
        
        $this->dbHost = $dbHost;
        $this->dbUser = $dbUser;
        $this->dbPass = $dbPass;
        $this->dbName = $dbName;
        
        try {
            // Enable mysqli errors to be thrown as Exceptions
            mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT);
            
            // Connect to MYSQL database
            $this->dbLink = mysqli_init();
            $this->dbLink->real_connect($this->dbHost, $this->dbUser, $this->dbPass, null, null, null, MYSQLI_CLIENT_FOUND_ROWS);
            $this->dbLink->set_charset("utf8");
            
            // Set sql_mode to ANSI
            $this->dbLink->query("SET SESSION sql_mode = 'ANSI,TRADITIONAL'");

        }catch (Exception $e){
            // Convert mysqli_sql_exceptions into 500 errors
            throw new Exception("Cannot connect to database", 500);
        }

        $this->selectDB();
    }

    protected function selectDB(){
        try {
            $this->dbLink->select_db($this->dbName);
        }catch (Exception $e){
            if(!Config::get('productionEnv')){
                switch ($e->getCode()){
                    case 1049 : // Error: 1049 SQLSTATE: 42000 (ER_BAD_DB_ERROR) --> Database ($this->dbName) does not (yet) exist
                        Logger::getLogger('DATABASE')->info("Automatically creating new database, because it does not exist");
                        $this->reinstallStorage();
                        break;
                    default : 
                        throw $e;
                }
            }else{
                throw $e;
            }
        }
    }
    
    /**
     * Function to create new database. Drops database (and loose all data) if already exists
     *
     * @return void
     */
    protected function createDB(){
        // Drop database
        $this->logger->info("Drop database if exists: '{$this->dbName}'");
        $this->dbLink->query("DROP DATABASE IF EXISTS {$this->dbName}");
        
        // Create new database
        $this->logger->info("Create new database: '{$this->dbName}'");
        $this->dbLink->query("CREATE DATABASE {$this->dbName} DEFAULT CHARACTER SET UTF8");

        $this->dbLink->select_db($this->dbName);
    }

    /**
     * The database is dropped, created again and all tables are created
     *
     * @return void
     */
    public function reinstallStorage(){
        $this->createDB();
        $structure = file_get_contents(Config::get('pathToGeneratedFiles') . 'database.sql');
        $this->logger->info("Execute database structure queries");
        $this->doQuery($structure, true);
    }
    
    /**
     * Return escaped mysql representation of Atom (identifier) according to Ampersand technical types (TTypes)
     * 
     * @throws Exception when technical type is not (yet) supported
     * @return mixed
     */
    protected function getDBRepresentation($atom){
        if(is_null($atom->id)) return null;
        
        switch($atom->concept->type){
            case "ALPHANUMERIC" :
            case "BIGALPHANUMERIC" :
            case "HUGEALPHANUMERIC" :
            case "PASSWORD" :
            case "TYPEOFONE" :
                return (string) $this->escape($atom->id);
            case "BOOLEAN" :
                return (int) $atom->id; // booleans are stored as tinyint(1) in the database. false = 0, true = 1
            case "DATE" :
                $datetime = new DateTime($atom->id);
                return $datetime->format('Y-m-d'); // format to store in database
            case "DATETIME" :
                // DateTime atom(s) may contain a timezone, otherwise UTC is asumed.
                $datetime = new DateTime($atom->id);
                $datetime->setTimezone(new DateTimeZone('UTC')); // convert to UTC to store in database
                return $datetime->format('Y-m-d H:i:s'); // format to store in database (UTC)
            case "FLOAT" :
                return (float) $atom->id;
            case "INTEGER" :
                return (int) $atom->id;
            case "OBJECT" :
                return $this->escape($atom->id);
            default :
                throw new Exception("Unknown/unsupported representation type '{$atom->concept->type}' for concept '[{$atom->concept}]'", 501);
        }
    }
    
    /**
     * Execute query on database. Function replaces reserved words by their corresponding value (e.g. _SESSION)
     * @param string $query
     * @return boolean|array
     * 
     * TODO:
     * Create private equivalent that is used by addAtom(), addLink(), deleteLink() and deleteAtom() functions, to perform any INSERT, UPDATE, DELETE
     * The public version should be allowed to only do SELECT queries.
     * This is needed to prevent Extensions or ExecEngine functions to go around the functions in this class that keep track of the affectedConjuncts.
     */
    public function Exe($query){
        $result = $this->doQuery($query);
        $this->logger->debug($query);

        if ($result === false) return false;
        elseif ($result === true) return true;
        
        $arr = array();
        while($row = mysqli_fetch_array($result)){
            $arr[] = $row;
        }
        return $arr;
        
    }
    
    /**
     * Execute query on database.
     * 
     * @param string $query
     * @param bool $multiQuery specifies if query is a single command or multiple commands concatenated by a semicolon 
     * @return mixed
     * @throws Exception
     */
    protected function doQuery($query, $multiQuery = false){
        $this->lastQuery = $query;
        try{
            if($multiQuery){
                $this->dbLink->multi_query($query);
                do { // to flush results, otherwise a connection stays open
                    if ($res = $this->dbLink->store_result()) $res->free();
                } while ($this->dbLink->more_results() && $this->dbLink->next_result());
                return true;
            }else{
                return $this->dbLink->query($query);
            }
        }catch (Exception $e){
            $this->logger->error($e->getMessage());
            if(!Config::get('productionEnv')){
                // Convert mysqli_sql_exceptions into 500 errors
                switch ($e->getCode()){
                    case 1146 : // Error: 1146 SQLSTATE: 42S02 (ER_NO_SUCH_TABLE)
                    case 1054 : // Error: 1054 SQLSTATE: 42S22 (ER_BAD_FIELD_ERROR)
                        throw new Exception("{$e->getMessage()}. Try <a href=\"#/admin/installer\" class=\"alert-link\">reinstalling database</a>",500);
                        break;
                    default:
                        throw new Exception("MYSQL error " . $e->getCode() . ": " . $e->getMessage() . " in query:" . $query, 500);
                        break;
                }
            }else{
                throw new Exception("Error in database query", 500);
            }
        }
    }
    
    /**
     * Escape identifier for use in database queries 
     * 
     * @param string $escapestr
     * @return NULL|string
     * 
     * http://php.net/manual/en/language.types.string.php#language.types.string.parsing
     * http://php.net/manual/en/mysqli.real-escape-string.php
     */
    public function escape($escapestr){
        if(is_null($escapestr)) return null;
        else return $this->dbLink->real_escape_string($escapestr);
    }

/**************************************************************************************************
 *
 * Implementation of StorageInterface methods (incl. database transaction handling)
 *
 *************************************************************************************************/
    
    /**
     * Returns name of storage implementation
     * @return string
     */
    public function getLabel(){
        return "MySQL database {$this->dbHost} - {$this->dbName}";
    }
    
    /**
     * Function to start/open a database transaction to track of all changes and be able to rollback
     * 
     * @param \Ampersand\Transaction $transaction
     * @return void
     */
    public function startTransaction(Transaction $transaction){
        if (!$this->dbTransactionActive){
            $this->logger->info("Start mysql database transaction for {$transaction}");
            $this->Exe("START TRANSACTION");
            return $this->dbTransactionActive = true; // set flag dbTransactionActive
        }
    }
    
    /**
     * Function to commit the open database transaction
     * 
     * @param \Ampersand\Transaction $transaction
     * @return void
     */
    public function commitTransaction(Transaction $transaction){
        $this->logger->info("Commit mysql database transaction for {$transaction}");
        $this->Exe("COMMIT");
        $this->dbTransactionActive = false;
    }
    
    /**
     * Function to rollback changes made in the open database transaction
     * 
     * @param \Ampersand\Transaction $transaction
     * @return void
     */
    public function rollbackTransaction(Transaction $transaction){
        $this->logger->info("Rollback mysql database transaction for {$transaction}");
        $this->Exe("ROLLBACK");
        $this->dbTransactionActive = false;
    }
    
/**************************************************************************************************
 * 
 * Implementation of ConceptPlugInterface methods
 *
 *************************************************************************************************/

    /**
    * Check if atom exists in database

    * @param \Ampersand\Core\Atom $atom
    * @return bool
    */
    public function atomExists(Atom $atom){
        $tableInfo = $atom->concept->getConceptTableInfo();
        $firstCol = current($tableInfo->getCols());
        $atomId = $this->getDBRepresentation($atom);
        
        $query = "/* Check if atom exists */ SELECT `$firstCol->name` FROM `{$tableInfo->name}` WHERE `$firstCol->name` = '{$atomId}'";
        $result = $this->Exe($query);
        
        if(empty($result)) return false;
        else return true;
    }
    
    /**
     * Get all atoms for given concept
     * 
     * @param \Ampersand\Core\Concept $concept
     * @return \Ampersand\Core\Atom[]
     */
    public function getAllAtoms(Concept $concept){
        $tableInfo = $concept->getConceptTableInfo();
        
        // Query all atoms in table
        if(isset($tableInfo->allAtomsQuery)) $query = $tableInfo->allAtomsQuery;
        else{
            $firstCol = current($tableInfo->getCols()); // We can query an arbitrary concept col for checking the existence of an atom
            $query = "SELECT DISTINCT `{$firstCol->name}` as `atomId` FROM `{$tableInfo->name}` WHERE `{$firstCol->name}` IS NOT NULL";
        }
        
        $arr = [];
        foreach ((array)$this->Exe($query) as $row){
            $tgtAtom = new Atom($row['atomId'], $concept);
            $tgtAtom->setQueryData($row);
            $arr[] = $tgtAtom;
        }
        return $arr;
    }
    
    /**
     * Add atom to database
     * 
     * @param \Ampersand\Core\Atom $atom
     * @return void
     */
    public function addAtom(Atom $atom){
        $atomId = $this->getDBRepresentation($atom);
                        
        // Get table properties
        $conceptTableInfo = $atom->concept->getConceptTableInfo();
        $conceptTable = $conceptTableInfo->name;
        $conceptCols = $conceptTableInfo->getCols(); // Concept are registered in multiple cols in case of specializations. We insert the new atom in every column.
        
        // Create query string: `<col1>`, `<col2>`, etc
        $allConceptCols = '`' . implode('`, `', $conceptTableInfo->getColNames()) . '`';
        
        
        // Create query string: '<newAtom>', '<newAtom', etc
        $atomIdsArray = array_fill(0, count($conceptCols), $atomId);
        $allValues = "'".implode("', '", $atomIdsArray)."'";
        
        $str = '';
        foreach($conceptCols as $col) $str .= ", `$col->name` = '{$atomId}'";
        $duplicateStatement = substr($str, 1);
        
        $this->Exe("INSERT INTO `$conceptTable` ($allConceptCols) VALUES ($allValues)"
                  ." ON DUPLICATE KEY UPDATE $duplicateStatement");
        
        // Check if query resulted in an affected row
        $this->checkForAffectedRows();
    }
    
    /**
     * Removing an atom as member from a concept set.
     * 
     * @param \Ampersand\Core\Atom $atom
     * @throws \Exception
     * @return void
     */
    public function removeAtom(Atom $atom){
        $atomId = $this->getDBRepresentation($atom);
        
        // Get col information for concept and its specializations
        $colNames = array();
        $conceptTableInfo = $concept->getConceptTableInfo();
        $conceptTable = $conceptTableInfo->name;
        $conceptCol = reset($conceptTableInfo->getCols());
        
        $colNames[] = $conceptCol->name;
        foreach($concept->getSpecializations() as $specConcept){
            $conceptTableInfo = $specConcept->getConceptTableInfo();
            $colNames[] = reset($conceptTableInfo->getColNames());
        }
        
        // Create query string: "<col1>" = '<atom>', "<col2>" = '<atom>', etc
        $queryString = "\"" . implode("\" = NULL, \"", $colNames) . "\" = NULL";
        
        $this->Exe("UPDATE \"$conceptTable\" SET $queryString WHERE \"{$conceptCol->name}\" = '{$atomId}'");
        
        // Check if query resulted in an affected row
        $this->checkForAffectedRows();
    }
    
    /**
     * Delete atom from concept table in the database
     * 
     * @param \Ampersand\Core\Atom $atom
     * @return void
     */
    public function deleteAtom(Atom $atom){
        $atomId = $this->getDBRepresentation($atom);
        
        // Delete atom from concept table
        $conceptTable = $atom->concept->getConceptTableInfo();
        $query = "DELETE FROM `{$conceptTable->name}` WHERE `{$conceptTable->getFirstCol()->name}` = '{$atomId}' LIMIT 1";
        $this->Exe($query);
        
        // Check if query resulted in an affected row
        $this->checkForAffectedRows();
    }

    /**
     * Rename an atom in the concept set (incl all specializations and generalizations)
     *
     * @param \Ampersand\Core\Atom $atom
     * @param string $newAtom
     * @return void
     */
    public function renameAtom(Atom $atom, $newAtomId){
        $atomId = $this->getDBRepresentation($atom);

        // Get table properties
        $table = $atom->concept->getConceptTableInfo()->name;
        $colNames = [];
        foreach($atom->concept->getGeneralizationsIncl() as $concept){
            $cols = $concept->getConceptTableInfo()->getColNames();
            $colNames[] = reset($cols);
        }
        $firstCol = reset($colNames);

        // Create query string: "<col1>" = '<atom>', "<col2>" = '<atom>', etc
        $queryString = "\"" . implode("\" = '{$newAtomId}', \"", $colNames) . "\" = '{$newAtomId}'";

        $this->Exe("UPDATE \"$table\" SET $queryString WHERE \"{$firstCol}\" = '{$atomId}'");

    }
    
/**************************************************************************************************
 *
 * Implementation of RelationPlugInterface methods
 *
 *************************************************************************************************/
    
    /**
    * Check if link exists in database

    * @param \Ampersand\Core\Link $link
    * @return bool
    */
    public function linkExists(Link $link){
        $relTable = $link->relation()->getMysqlTable();
        $srcAtomId = $this->getDBRepresentation($link->src());
        $tgtAtomId = $this->getDBRepresentation($link->tgt());
        
        $result = $this->Exe("/* Check if link exists */ SELECT * FROM `{$relTable->name}` WHERE `{$relTable->srcCol()->name}` = '{$srcAtomId}' AND `{$relTable->tgtCol()->name}` = '{$tgtAtomId}'");
        
        if(empty($result)) return false;
        else return true;
    }
    
    /**
    * Get all links given a relation

    * @param \Ampersand\Core\Relation $relation
    * @param \Ampersand\Core\Atom $srcAtom if specified get all links with $srcAtom as source
    * @param \Ampersand\Core\Atom $tgtAtom if specified get all links with $tgtAtom as tgt
    * @return \Ampersand\Core\Link[]
    */
    public function getAllLinks(Relation $relation, Atom $srcAtom = null, Atom $tgtAtom = null){
        $relTable = $relation->getMysqlTable();
        
        // Query all atoms in table
        $query = "SELECT `{$relTable->srcCol()->name}` as `src`, `{$relTable->tgtCol()->name}` as `tgt` FROM `{$relTable->name}`";
        
        // Construct WHERE-clause if applicable
        if(isset($srcAtom)) $query .= " WHERE `{$relTable->srcCol()->name}` = '{$this->getDBRepresentation($srcAtom)}'";
        else $query .= " WHERE `{$relTable->srcCol()->name}` IS NOT NULL";

        if(isset($tgtAtom)) $query .= " AND `{$relTable->tgtCol()->name}` = '{$this->getDBRepresentation($tgtAtom)}'";
        else $query .= " AND `{$relTable->tgtCol()->name}` IS NOT NULL";
        
        $links = [];
        foreach((array)$this->Exe($query) as $row){
            $links[] = new Link($relation, new Atom($row['src'], $relation->srcConcept), new Atom($row['tgt'], $relation->tgtConcept));
        }
        
        return $links;
    }
    
    /**
     * Add link (srcAtom,tgtAtom) into database table for relation r
     * 
     * @param \Ampersand\Core\Link $link
     * @return void
     */
    public function addLink(Link $link){
        $relation = $link->relation();
        $srcAtomId = $this->getDBRepresentation($link->src());
        $tgtAtomId = $this->getDBRepresentation($link->tgt());
        
        $relTable = $relation->getMysqlTable();
        
        switch ($relTable->tableOf){
            case null : // Relation is administrated in n-n table
                $this->Exe("REPLACE INTO `{$relTable->name}` (`{$relTable->srcCol()->name}`, `{$relTable->tgtCol()->name}`) VALUES ('{$srcAtomId}', '{$tgtAtomId}')");
                break;
            case 'src' : // Relation is administrated in concept table (wide) of source of relation
                $this->Exe("UPDATE `{$relTable->name}` SET `{$relTable->tgtCol()->name}` = '{$tgtAtomId}' WHERE `{$relTable->srcCol()->name}` = '{$srcAtomId}'");
                break;
            case 'tgt' : //  Relation is administrated in concept table (wide) of target of relation
                $this->Exe("UPDATE `{$relTable->name}` SET `{$relTable->srcCol()->name}` = '{$srcAtomId}' WHERE `{$relTable->tgtCol()->name}` = '{$tgtAtomId}'");
                break;
            default :
                throw new Exception ("Unknown 'tableOf' option for relation '{$relation}'", 500);
        }
        
        // Check if query resulted in an affected row
        $this->checkForAffectedRows();
    }
    
    /**
     * Delete link (srcAtom,tgtAtom) into database table for relation r
     * 
     * @param \Ampersand\Core\Link $link
     * @return void
     */
    public function deleteLink(Link $link){
        $relation = $link->relation();
        $srcAtomId = $this->getDBRepresentation($link->src());
        $tgtAtomId = $this->getDBRepresentation($link->tgt());
         
        $relTable = $relation->getMysqlTable();
         
        switch ($relTable->tableOf){
            case null : // Relation is administrated in n-n table
                if(is_null($srcAtomId) || is_null($tgtAtomId)) throw new Exception ("Cannot delete from relation table '{$relTable->name}', because srcAtom or tgtAtom is null", 500);
                $this->Exe("DELETE FROM `{$relTable->name}` WHERE `{$relTable->srcCol()->name}` = '{$srcAtomId}' AND `{$relTable->tgtCol()->name}` = '{$tgtAtomId}'");
                break;
            case 'src' : // Relation is administrated in concept table (wide) of source of relation
                if(!$relTable->tgtCol()->null) throw new Exception("Cannot delete link {$link} because target column '{$relTable->tgtCol()->name}' in table '{$relTable->name}' may not be set to null", 500);
                
                // Source atom can be used in WHERE statement
                if(!is_null($srcAtomId)) $this->Exe("UPDATE `{$relTable->name}` SET `{$relTable->tgtCol()->name}` = NULL WHERE `{$relTable->srcCol()->name}` = '{$srcAtomId}'");
                // Target can be used in WHERE statement, because tgtCol is unique
                elseif($relTable->tgtCol()->unique) $this->Exe("UPDATE `{$relTable->name}` SET `{$relTable->tgtCol()->name}` = NULL WHERE `{$relTable->tgtCol()->name}` = '{$tgtAtomId}'");
                // Else update cannot be performed, because of missing target
                else throw new Exception ("Cannot set '{$relTable->tgtCol()->name}' to NULL in concept table '{$relTable->name}', because srcAtom is null", 500);
                break;
            case 'tgt' : //  Relation is administrated in concept table (wide) of target of relation
                if(!$relTable->srcCol()->null) throw new Exception("Cannot delete link {$link} because source column '{$relTable->srcCol()->name}' in table '{$relTable->name}' may not be set to null", 500);
                
                // Target atom can be used in WHERE statement
                if(!is_null(($tgtAtomId))) $this->Exe("UPDATE `{$relTable->name}` SET `{$relTable->srcCol()->name}` = NULL WHERE `{$relTable->tgtCol()->name}` = '{$tgtAtomId}'");
                // Source can be used in WHERE statement, because srcCol is unique
                elseif($relTable->srcCol()->unique) $this->Exe("UPDATE `{$relTable->name}` SET `{$relTable->srcCol()->name}` = NULL WHERE `{$relTable->srcCol()->name}` = '{$srcAtomId}'");
                // Else update cannot be performed, because of missing target
                else throw new Exception ("Cannot set '{$relTable->srcCol()->name}' to NULL in concept table '{$relTable->name}', because tgtAtom is null", 500);
                break;
            default :
                throw new Exception ("Unknown 'tableOf' option for relation '{$relation}'", 500);
        }
        
        $this->checkForAffectedRows(); // Check if query resulted in an affected row
    }
    
    /**
     * 
     * 
     * @param \Ampersand\Core\Relation $relation relation from which to delete all links
     * @param \Ampersand\Core\Atom $atom atom for which to delete all links
     * @param string $srcOrTgt specifies to delete all link with $atom as src, tgt or both (null/not provided)
     * @return void
     */
    public function deleteAllLinks(Relation $relation, Atom $atom = null, $srcOrTgt = null){
        $relationTable = $relation->getMysqlTable();
        
        // Delete links for given atom
        if(isset($atom)){
            $atomId = $this->getDBRepresentation($atom);
            
            $cols = [];
            switch ($srcOrTgt) {
                case 'src':
                    $cols[] = $relationTable->srcCol();
                    break;
                case 'tgt':
                    $cols[] = $relationTable->tgtCol();
                    break;
                case null:
                    $cols[] = $relationTable->srcCol();
                    $cols[] = $relationTable->tgtCol();
                    breal;
                default:
                    throw new Exception("Unknown/unsupported param option '{$srcOrTgt}'. Supported options are 'src', 'tgt' or null", 500);
                    break;
            }
            
            foreach($cols as $col){
                // If n-n table, remove row
                if(is_null($relationTable->tableOf)) $query = "DELETE FROM `{$relationTable->name}` WHERE `{$col->name}` = '{$atomId}'";
                
                // Elseif column may be set to null, update
                elseif($col->null) $query = "UPDATE `{$relationTable->name}` SET `{$col->name}` = NULL WHERE `{$col->name}` = '{$atomId}'";
                
                // Else, we remove the entire row (cascades delete for TOT and SUR relations)
                else $query = "DELETE FROM `{$relationTable->name}` WHERE `{$col->name}` = '{$atomId}'";
                
                $this->Exe($query);
            }
            
        // Delete all links
        }else{
            // If n-n table, remove all rows
            if(is_null($relationTable->tableOf)){
                $query = "DELETE FROM `{$relationTable->name}`";
            
            // Else if in table of src concept, set tgt col to null
            }elseif($relationTable->tableOf == 'src'){ 
                $col = $relationTable->tgtCol();
                $query = "UPDATE `{$relationTable->name}` SET `{$col->name}` = NULL";
            
            // Else if in table of tgt concept, set src col to null
            }elseif($relationTable->tableOf == 'tgt'){ 
                $col = $relationTable->srcCol();
                $query = "UPDATE `{$relationTable->name}` SET `{$col->name}` = NULL";
            }
            
            $this->Exe($query);
        }
        
    }
    
/**************************************************************************************************
 *
 * Implementation of PlugInterface methods
 *
 *************************************************************************************************/
    
    /**
     * Execute query for given interface expression and source atom
     * 
     * @param \Ampersand\Interfacing\InterfaceObject $ifc
     * @param \Ampersand\Core\Atom $srcAtom
     * @return mixed
     */
    public function executeIfcExpression(InterfaceObject $ifc, Atom $srcAtom = null){
        $srcAtomId = $this->getDBRepresentation($srcAtom);
        $query = $ifc->getQuery();

        if(strpos($query, '_SRCATOM') !== false){
            $query = str_replace('_SRCATOM', $srcAtomId, $query);
        }else{
            $query = "SELECT DISTINCT * FROM ({$query}) AS `results` WHERE `src` = '{$srcAtomId}' AND `tgt` IS NOT NULL";
        }
        return $this->Exe($query);
    }
    
    /**
     * Execute query for giver view segement and source atom
     * 
     * @param \Ampersand\Interfacing\ViewSegment $view
     * @param \Ampersand\Core\Atom $srcAtom
     * @return array
     */
    public function executeViewExpression(ViewSegment $view, Atom $srcAtom = null): array {
        $srcAtomId = $this->getDBRepresentation($srcAtom);
        $viewSQL = $view->getQuery();
        
        $query = "SELECT DISTINCT `tgt` FROM ({$viewSQL}) AS `results` WHERE `src` = '{$srcAtomId}' AND `tgt` IS NOT NULL";
        return array_column((array) $this->Exe($query), 'tgt');
    }
    
/**************************************************************************************************
 *
 * Helper functions
 *
 *************************************************************************************************/
    
    /**
     * Check if insert/update/delete function resulted in updated record(s). If not, report warning (or throw exception) to indicate that something is going wrong
     * 
     * @throws \Exception when no records are affected and application is not in production mode
     * @return void
     */
    protected function checkForAffectedRows(){
        if($this->dbLink->affected_rows == 0){
            if(Config::get('productionEnv')){
                $this->logger->warning("No recors affected with query '{$this->lastQuery}'");
            }else{
                throw new Exception ("Oops.. something went wrong. No records affected in database", 500);
            }
        } 
    }
}
