{-# LANGUAGE CPP #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ViewPatterns #-}

#include "thyme.h"
#if HLINT
#include "cabal_macros.h"
#endif

module Data.Thyme.Format.Human
    ( humanTimeDiff
    , humanTimeDiffs
    , humanRelTime
    , humanRelTimes
    ) where

import Prelude
#if !MIN_VERSION_base(4,8,0)
import Control.Applicative
#endif
import Control.Arrow
import Control.Lens
import Control.Monad
import Data.AdditiveGroup
import Data.AffineSpace
import Data.Foldable
import Data.Thyme.Internal.Micro
import Data.Monoid
import Data.Thyme.Clock.Internal
import Data.VectorSpace

data Unit = Unit
    { unit :: Micro
    , single :: ShowS
    , plural :: ShowS
    }
LENS(Unit,plural,ShowS)

-- | Display 'DiffTime' or 'NominalDiffTime' in a human-readable form.
{-# INLINE humanTimeDiff #-}
humanTimeDiff :: (TimeDiff d) => d -> String
humanTimeDiff d = humanTimeDiffs d ""

-- | Display 'DiffTime' or 'NominalDiffTime' in a human-readable form.
{-# ANN humanTimeDiffs "HLint: ignore Use fromMaybe" #-}
humanTimeDiffs :: (TimeDiff d) => d -> ShowS
humanTimeDiffs td = (if signed < 0 then (:) '-' else id) . diff where
    signed@(Micro . abs -> us) = td ^. microseconds
    diff = maybe id id . getFirst . fold $
        zipWith (approx us . unit) (tail units) units

-- | Display one 'UTCTime' relative to another, in a human-readable form.
{-# INLINE humanRelTime #-}
humanRelTime :: UTCTime -> UTCTime -> String
humanRelTime ref time = humanRelTimes ref time ""

-- | Display one 'UTCTime' relative to another, in a human-readable form.
humanRelTimes :: UTCTime -> UTCTime -> ShowS
humanRelTimes ref time = thence $ humanTimeDiffs diff where
    (diff, thence) = case compare delta zeroV of
        LT -> (negateV delta, ((++) "in " .))
        EQ -> (zeroV, const $ (++) "right now")
        GT -> (delta, (. (++) " ago"))
        where delta = time .-. ref

approx :: Micro -> Micro -> Unit -> First ShowS
approx us next Unit {..} = First $
        shows n . inflection <$ guard (us < next) where
    n = fst $ microQuotRem (us ^+^ half) unit where
        half = Micro . fst $ microQuotRem unit (Micro 2)
    inflection = if n == 1 then single else plural

units :: [Unit]
units = scanl (&)
    (Unit (Micro 1) (" microsecond" ++) (" microseconds" ++))
    [ times "millisecond"   1000
    , times "second"        1000
    , times "minute"        60
    , times "hour"          60
    , times "day"           24
    , times "week"          7
    , times "month"         (30.4368 / 7)
    , times "year"          12
    , times "decade"        10
    , times "century"       10 >>> set _plural (" centuries" ++)
    , times "millennium"    10 >>> set _plural (" millennia" ++)
    , const (Unit maxBound id id) -- upper bound needed for humanTimeDiffs.diff
    ] where
    times :: String -> Rational -> Unit -> Unit
    times ((++) . (:) ' ' -> single) r Unit {unit}
        = Unit {unit = r *^ unit, plural = single . (:) 's', ..}

