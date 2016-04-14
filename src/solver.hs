module Solver where

import Prelude hiding (lookup, minBound)

import Data.List (sortBy)

import Data.Bool
import Data.Maybe

import qualified Data.Map as Map
import qualified Data.Time as Time

import Structures
import FileReader

main :: IO ()
main = do
    pb <- getPb
    putStrLn "Initial Problem : "
    putStrLn $ show $ pb
    putStrLn "Final solution : "
    time <- Time.getCurrentTime >>= return . Time.utctDayTime
    sol <- improveSolution' pb (time + 20*60)
    putStrLn $ showSolution $ sol
    return ()

{-
Branch and bound :
    Si la solution est pas réalisable :
        retour + enlever cette possibilité
    Si la soltion est finie :
        Si meilleur solution :
                l'enregistrer
            Sinon
                retour
        Sinon
            retour
    Trouver la borne min du début de solution :
    Si borne min > solution déjà existante
        retour + enlever cette possibilité
    Sinon
        Trouver le transport le moins chère possible
        Si possible de faire un nouveau transport
            le faire, recursion
        Sinon
            retour
-}
{-
improveSolution :: Problem -> Int -> Problem
improveSolution pb i
    | i <= 0 = pb
    | isSoltionOver pb = if isBestSolution pb
        then newBestSolution pb
        else pb
    | minBound pb > pb_bestSolutionCost pb && pb_bestSolutionCost pb > 0 = pb
    | otherwise = if isJust path
        then improveSolution (removePossiblility (copyThebest pb $ improveSolution newProblem (i)) path) (i-1)
        else pb
        where
            path = findPath pb :: Path
            newProblem = usePath pb path :: Problem
-}
improveSolution' :: Problem -> Time.DiffTime -> IO Problem
improveSolution' pb endTime = do
    time <- Time.getCurrentTime >>= return . Time.utctDayTime
    if endTime < time
        then return pb
        else if isSoltionOver pb
            then if isBestSolution pb
                then newBestSolution pb
                else return pb
            else if minBound pb > pb_bestSolutionCost pb && pb_bestSolutionCost pb > 0
                then return pb
                else do
                    let path = findPath pb
                    if isJust path
                    then do
                        newProblem <- improveSolution' (usePath pb path) endTime;
                        improveSolution' (removePossiblility (copyBestSol pb newProblem) path) endTime
                    else return pb

{-
    Compute the cost of the pb_solution of a given problem
-}
coutSolution :: Problem -> Int
coutSolution Problem {pb_nodes=nodes, pb_edges=edges, pb_solution=sol} =
    foldl (\acc x -> acc + coutElem x ) 0 $ Map.assocs sol where
        coutElem (idEdge, nbrUtilisation)
            | nbrUtilisation == 0 = 0
            | otherwise = (e_c edge) + ((n_g startingNode)+(e_h edge)) * nbrUtilisation
                where
                    edge = edges Map.! idEdge
                    startingNode = nodes Map.! (e_start edge)

{-
    add `nbr` elements on the edge of index `idx`
-}
addTransport :: Problem -> Int -> Int -> Problem
addTransport pb idx nbr = pb{pb_solution = Map.insert idx nbr' (pb_solution pb),
                             pb_edges = Map.insert idx (useEdge edge nbr') (pb_edges pb),
                             pb_nodes = move (pb_nodes pb) (e_start edge) (e_end edge) nbr}
        where
            edge = (pb_edges pb) Map.! idx
            nbr' = if Map.member idx $ pb_solution pb then nbr + pb_solution pb Map.! idx else nbr
            useEdge :: Edge -> Int -> Edge
            useEdge edge nbr = edge{e_a = nbr}
            move :: Map.Map Int Node -> Int -> Int -> Int -> Map.Map Int Node
            move map_edges from to nbr = Map.insert from (changeCapacityNode from nbr) (Map.insert to (changeCapacityNode to (-nbr)) map_edges) where
                changeCapacityNode :: Int -> Int -> Node
                changeCapacityNode n_idx nbr = node{n_b=(n_b node) + nbr} where
                    node = getNode pb n_idx
{-
    #########################
    Check if the actual (partial ??) solution can lead to a feasible solution
-}
isSolutionRealisable :: Problem -> Bool
isSolutionRealisable pb = True

{-
    Check if the actual solution transport every element from the repository to the clients
-}
isSoltionOver :: Problem -> Bool
isSoltionOver Problem {pb_maxTime=maxTime, pb_nodes=nodes, pb_edges=edges, pb_solution=sol} =
    foldl (\acc x -> if n_b x == 0 then acc else False) True $ Map.elems nodes

{-
    Save the actual solution as the best solution, compute the cost of the best solution
-}
newBestSolution :: Problem -> IO Problem
newBestSolution pb = do
    let pb2 = pb {pb_bestSolution=pb_solution pb, pb_bestSolutionCost=coutSolution pb}
    putStrLn $ showSolution pb2
    return pb2

{-
    Check if the actual solution is betten than the actual best solution
-}
isBestSolution :: Problem -> Bool
isBestSolution pb =  pb_bestSolutionCost pb == 0 || coutSolution pb < pb_bestSolutionCost pb

{-
    #########################
    Compute the minimal bound of a solution
-}

minBound :: Problem -> Int
minBound pb = coutSolution pb + estimatedCost where
        estimatedCost = sum $ map nodeEstimation $ Map.elems $ pb_nodes pb where
            nodeEstimation :: Node -> Int
            nodeEstimation node = fillNode (abs $ n_b node) $ sortBy (\a b -> compare (cmup a) (cmup b)) edges where
                cmup :: Edge -> Int
                cmup edge = e_h edge * e_u edge + if isNothing $ (e_id edge) `Map.lookup` (pb_solution pb)
                    then e_c edge   -- Si pas encore utilisé
                    else 0          -- si déjà utilisé
                edges = if n_b node < 0 --Repository
                    then [x | x <- Map.elems $ pb_edges pb, e_start x == n_id node]
                    else if n_b node > 0 -- Client
                        then [x | x <- Map.elems $ pb_edges pb, e_end x == n_id node]
                        else [] -- finished / platform
                fillNode :: Int -> [Edge] -> Int
                fillNode nbr [] = 0
                fillNode nbr (x:xs) = if nbr <= 0
                    then 0
                    else (if e_a x==0 then e_c x else 0) + e_h x * nbr' + fillNode (nbr - nbr') xs where
                        nbr' = min nbr (e_u x - e_a x)

{-
    Reduce the number of possiblility of a problem
-}
removePossiblility :: Problem -> Path -> Problem
removePossiblility pb Nothing = pb
removePossiblility pb (Just(_, _, 0)) = pb
removePossiblility pb (Just(a, b, c)) = pb {pb_edges= Map.insert (e_id lower) (decrement lower) (pb_edges pb)}
    where
        ea = (pb_edges pb) Map.! a :: Edge
        eb = (pb_edges pb) Map.! b :: Edge
        lower = if pb `remainingCapacity` a <= pb `remainingCapacity` b then ea else eb :: Edge
        decrement :: Edge -> Edge
        decrement e = e{e_u=(e_u e)-1} -- =0

{-
    Return the best possible path to use
    Returned value : Just (id_edge 1, id_edge2, nbrProduct) | Nothing if there is no remaining path
-}
findPath :: Problem -> Path
findPath pb = if null res then Nothing else res !! 0 where
    res = sortBy costOrder $ concat . map pathFrom $ Map.elems $ pb_nodes pb
    pathFrom :: Node -> [Path]
    pathFrom n = if n_b n >= 0 then [] --Get every possible transport from a node
        else concat . filter (/=[]) $ map pathWith $ Map.elems $ pb_edges pb where
            pathWith :: Edge -> [Path]
            pathWith e = if n_id n == e_start e && e_a e <= e_u e -- start from n && can add product
                then filter isJust $ map pathWith' $ Map.elems $ pb_edges pb
                else []
                where
                    pathWith' :: Edge -> Path
                    pathWith' e2 = if e_end e == e_start e2 && e_a e2 <= e_u e2 && time <= pb_maxTime pb && nbr > 0
                        then path
                        else Nothing
                        where
                            nbr = minimum [e_u e - e_a e, e_u e2 - e_a e2,-(n_b $ getNode pb (e_start e)), n_b $ getNode pb (e_end e2)]
                            time = e_t e + e_t e2 + (n_s $ getNode pb (e_end e))
                            path = Just(e_id e, e_id e2, nbr)
    costOrder :: Path -> Path -> Ordering
    costOrder p1 p2 = compare (costPath p1) (costPath p2) where
        costPath :: Path -> Int
        costPath Nothing = 0
        costPath (Just(e1, e2, nbr)) = (costEdge (getEdge pb e1) nbr) + (costEdge (getEdge pb e2) nbr) + n_g (getNode pb e1) where
            costEdge :: Edge -> Int -> Int
            costEdge Edge{e_c=c, e_h=h, e_a=a} nbr = (if a == 0 then c else 0) + h*nbr


findPath' pb = concat . map pathFrom $ Map.elems $ pb_nodes pb where
    pathFrom :: Node -> [Path] --Get every possible transport from a node -- if not a repository : nothing
    pathFrom n = if n_b n >= 0 then [] -- if not a repository : nothing
        else concat $ map pathWith $ Map.elems $ pb_edges pb where
            pathWith :: Edge -> [Path]
            pathWith e = if n_id n == e_start e && e_a e <= e_u e -- start from n && can add product
                then filter isJust $ map pathWith' $ Map.elems $ pb_edges pb
                else []
                where
                    pathWith' :: Edge -> Path
                    pathWith' e2 = if True --e_end e == e_start e2 && e_a e2 <= e_u e2 && time <= pb_maxTime pb && nbr > 0
                        then path
                        else Nothing
                        where
                            nbr = minimum [e_u e - e_a e, e_u e2 - e_a e2,-(n_b $ getNode pb (e_start e)), n_b $ getNode pb (e_end e2)]
                            time = e_t e + e_t e2 + (n_s $ getNode pb (e_end e))
                            path = Just(e_id e, e_id e2, nbr)
    costOrder :: Path -> Path -> Ordering
    costOrder p1 p2 = compare (costPath p1) (costPath p2) where
        costPath :: Path -> Int
        costPath Nothing = 0
        costPath (Just(e1, e2, nbr)) = (costEdge (getEdge pb e1) nbr) + (costEdge (getEdge pb e2) nbr) + n_g (getNode pb e1) where
            costEdge :: Edge -> Int -> Int
            costEdge Edge{e_c=c, e_h=h, e_a=a} nbr = (if a == 0 then c else 0) + h*nbr
{-
    Return the remaining capacity of the edge of index `edgeIdx` in the Problem pb
-}
remainingCapacity :: Problem -> Int -> Int
remainingCapacity pb edgeIdx = if isNothing mb_usage
    then capacity
    else capacity - fromJust mb_usage
    where
        capacity = e_u $ (pb_edges pb) Map.! edgeIdx :: Int
        mb_usage = edgeIdx `Map.lookup` (pb_solution pb) :: Maybe Int

{-
    add a path to solutions
-}
usePath :: Problem -> Path -> Problem
usePath pb Nothing = pb{pb_path=Nothing:(pb_path pb)}
usePath pb (Just (a, b, c)) = (addTransport (addTransport pb b c) a c){pb_path = (Just (a, b, c)):(pb_path pb)}

copyBestSol :: Problem -> Problem -> Problem
copyBestSol pb Problem {pb_bestSolution=best, pb_bestSolutionCost=cost} = pb{pb_bestSolution=best, pb_bestSolutionCost=cost}