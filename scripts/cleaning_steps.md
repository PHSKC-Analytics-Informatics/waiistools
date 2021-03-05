### PHSKC's Data Cleaning Process for weekly IIS extracts

#### General assumptions
- When race is specified as 'Unknown' and 'Other', this is considered a lack of good data rather than a true designation of those categories. In general, these values are considered missing during data cleaning and are replaced with other race information if available. There is a chance certain people did legitimately select 'Other' as a race and as such will be miscategorized if there is any indication that the individual provided other race data. 

#### Remove a priori bad records
1. Remove instances where `VaccinationRefusal` is 'Yes'

#### Clean up `WaiisEntryDate`
2. If `WaiisEntryDate` is NA, fill in using `WaiisInsertDate`
3. Fill in missing entries after step 1 with `AdministrationDate`

#### Construct race variable
4. Race is initially constructed for `IISRace1`
5. if any of `IISRace2` - `IISRace3` are not NA and are not 6 (for other) and are not equal to `IISRace1`, change race to 8 (for Multiple race).

#### Filling NAs and update other data with more recent information
6. Where possible, standardize race data within a patient, choosing the most recent entry that is not "Unknown", or "Other". "Other" is selected over "Unknown" when there is not a better option.
7. Standardize ethnicity data based on the last observed valid record per patient
8. Standardize ZIP code data based on last observed valid record per patient
9. Standardize birthday data based on last observed valid record per patient
10. Vaccine manufacturer is derived from `CVX` and supplemented by `MVX` when `CVX` is missing. Any remaining doses without manufacturer are filled by a last observation carried forward sweep and then a next observation carried backward where there is more than one recorded dose.

TODO: standardize mfg between doses/figure out logic for doses from different mfg.

#### Remove duplicates
11. When there are two vaccine dates within 6 days of each other, the latter dose is selected based on a descending sort on `AdministrationDate` and `WaiisEntryDate`
12. For patients with 3+ doses for a two dose regime, keep the first dose and 2+ dose that best matches the ideal span (21 days for Pfizer and 28 for Moderna)
13. For patients with >1 dose for a one dose regime, keep only the first dose.