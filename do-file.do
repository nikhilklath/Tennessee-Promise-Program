*****************************************
* Name: Nikhil Kumar					*
* Date: 11/15/2020						*
*****************************************

clear all

* How can you run this file?
* Just change the path of the working folder in the next line
global projdir "C:\Users\nikhi\Downloads\Task"

* raw data folder
global raw "$projdir\Raw Data"

* folder where clean data is saved
global final "$projdir\Clean Data"

* folder where ouptut graphs and tables are saved
global output "$projdir\Output"

cd "$raw"

********************************************************************************
* 							CREATE PANEL DATA								   *


/*
Assemble a panel data set tracking enrollment and aid awards at Tennessee colleges over time

First, I import “Directory Information” files from the “Institutional Characteristics” survey,
append them after adding a year variable
and create a panel dataset from these files
*/ 

scalar flag = 1 //flag for the first run of the loop
forvalues i=2010/2015{ //loop over every year we have data for
	
	if(flag==1){ // if first run of loop
		
		import delimited "schools\hd`i'.csv", numericcols(5) clear 
		
		gen year = `i' //add a variable for the year in the dataset
		
		tempfile yourfilename //declare the temporary file 
		sa `yourfilename' // save the first csv file in a temporary file
		scalar flag = 0 // indicate for further iterations that it is not the first run
	}
	
	else{
	    
		import delimited "schools\hd`i'.csv", numericcols(5) clear
		
		gen year = `i' //add a variable for the year in the dataset
		
		append using `yourfilename' // append to the exisiting temporary file
		sa `yourfilename', replace // replace the temporary file
	}
}

rename unitid ID_IPEDS //rename the variable unitid and save the panel data
save "$final\directory_panel.dta", replace // save this dataset

/*
The "Student Financial Aid and Net Price" data is in a wide format.
So, I first reshape the dataset into long form with a new year variable.
Then, merge this long data with the previously created panel.
*/

import delimited "students\sfa1015.csv", clear 
reshape long scugrad scugffn scugffp fgrnt_a fgrnt_p sgrnt_p sgrnt_a, i(unitid) j(year) // reshape the data into long form
rename unitid ID_IPEDS //rename the variable unitid and save the panel data
save "$final\grant_aid_panel.dta", replace  // save this dataset

merge 1:1 ID_IPEDS year using "$final/directory_panel.dta" // merge the two datasets using ID_IPEDS and year as primary key
keep if _merge == 3 // keep only those institutions for which both grant data and college characterisitcs are available

/* Restrict the sample to undergraduate institutions
The codebook says that institutions with instcat values 2, 3, 4 and 6 
offer bachelor's and associate degrees, as well as diplomas and certificates.
*/
keep if inlist(instcat, 2, 3, 4, 6) // keep undergraduate institutions

gen degree_bach = ((instcat == 2) | (instcat ==3)) // a dummy variable that identifies bachelor's degree-granting institutions

gen public = control == 1 //a dummy variable that identifies public institutions

rename scugffn enroll_ftug // rename the variable for the total number of first-time, full-time undergraduates as required

gen grant_state = sgrnt_a * enroll_ftug // total amount of state and local grant aid awarded to first-time, full-time undergraduates

gen grant_federal = fgrnt_a * enroll_ftug //total amount of federal grant aid awarded to first-time, full-time undergraduates

drop if fgrnt_a ==. // drop observations for which grant information is not available

keep ID_IPEDS year degree_bach public enroll_ftug grant_state grant_federal // keep the variable that are required for analysis

* label the variables
label var ID_IPEDS "a unique identifier for each institution"
label var year "the 4-digit academic year, where “2010-11” is coded as 2010, and so on"
label var degree_bach "a dummy variable that identifies bachelor's degree-granting institutions"
label var public "a dummy variable that identifies public institutions"
label var enroll_ftug "the total number of first-time, full-time undergraduates"
label var grant_state "total amt of state/local grant aid awarded to first-time, full-time UGs"
label var grant_federal "total amt of federal grant aid awarded to first-time, full-time UGs"

* save the panel dataset
save "$final\final_panel_data.dta", replace 

********************************************************************************
* 								ANALYSIS									   *
/*
The Tennessee Promise guarantees no-cost tuition for all Tennessee high school graduates who attend the state's public community and technical colleges. For the sake of concision, we'll refer to schools that offer bachelor's degrees as “four-year colleges” and schools that don't as “two-year colleges.” (We recognize that, in practice, time to degree completion varies widely across students and credentials). We'll also distinguish between public and private schools, so your analysis will compare four groups:
● public, two-year colleges
● public, four-year colleges
● private, two-year colleges
● private, four-year colleges
Given these categories, community and technical colleges will fall in the “public, two-year” group.
*/

* generate dummy for groups of colleges 

* group 1 = public 2 year colleges
gen group = 1 if ((public == 1) & (degree_bach == 0))

* group 2 = public 4 year colleges
replace group = 2 if ((public == 1) & (degree_bach == 1))

* group 3 = private 2 year colleges
replace group = 3 if ((public == 0) & (degree_bach == 0))

* group 4 = private 4 year colleges
replace group = 4 if ((public == 0) & (degree_bach == 1))

* labels for the various groups
label define group 1 "public 2 year college" 2 "public 4 year college" 3 "private 2 year college" 4 "private 4 tear college"

* summarize state/federal grants to schools in the year 2015 when Tenessee Promise program was started
bys group: sum grant_state if year == 2015

* summarize enrollment in schools in the year 2015 when Tenessee Promise program was started
bys group: sum enroll_ftug if year == 2015

* Graph that compares average school-level state plus local grant aid across the four types of institutions during the sample period
graph hbar grant_state if year==2015, over(group, relabel(1 "public 2 year college" 2 "public 4 year college" 3 "private 2 year college" 4 "private 4 year college")) ytitle("Average school-level state plus local grant aid") ylabel(2000000 "2 million" 4000000 "4 million" 6000000 "6 million")
graph save "$output\avg_grant_state_across_groups.gph", replace

* Graph that compares average school-level enrollment of first-time, full-time undergraduates across the four types of institutions during the sample period
graph hbar enroll_ftug if year==2015, over(group, relabel(1 "public 2 year college" 2 "public 4 year college" 3 "private 2 year college" 4 "private 4 year college")) ytitle("Average school-level enrollment of first-time, full-time UGs")
graph save "$output\avg_enroll_ftug_across_groups.gph", replace

/*
From the two bar charts, we can observe that higher Average school-level state plus local grant aid is associated with higher average school-level enrollment of first-time, full-time Undergraduates
*/

scatter enroll_ftug grant_state if year==2015, xtitle(local/state grant aid) ytitle(enrolment)
graph save "$output\plot1.gph", replace

/*

A regression model that will generate a numeric estimate of the causal effect of the Tennessee Promise program on enrollment at public, two-year colleges.

from the scatterplot (plot1.gph) of school-level enrollment of first-time, full-time undergraduates 
against school-level state plus local grant aid,  we can see a relationship between the two variables. 
Therefore, this grant_state will be a control in our regression model. 
Similarly, I also expect that grant_federal will also affect enrollment and hence serve as a control.

I run a difference-in-differences regression model with public-2 year colleges in treatment group 
with treatment assignment in 2015.
*/

gen post = year == 2015
gen treat = group == 1

/*
In the regression, I also control for total state/local grant and total federal grant
*/

/*
I compare public-2 year colleges with private 2-year colleges because 
2-year colleges cater to students with means and ambitions 
that may be different from 4-year colleges.

Since public-2 year colleges and private 2-year colleges cater to a similar student population, 
I expect them to be comparable groups.
*/
keep if inlist(group, 1,3) // keep only 2 year colleges both public and private
reg enroll_ftug post##treat grant_state grant_federal

/*
We can say that, on average, being the Tennessee Promise program in 2015 caused a drop 
in enrollment by about 19 students, compared to not being in the program in 2015.
*/
outreg2 using "$output\myreg.txt", replace



****************************************************************************************
* demographic characteristics of Tennessee high school students in school year 2019 - 20

clear all
import excel "$raw\high school demographics\membership201920.xlsx", firstrow 
// this datset has been downloaded from the state government's website

* drop aggregate values for gender and race
drop if GENDER == "All Genders"
drop if RACE == "All Race/Ethnic Groups"

collapse (sum) ENROLLMENT, by(GENDER RACE GRADE) // add enrollment numbers for each gender-race-age group

sort GRADE RACE GENDER

keep if inlist(GRADE, "09", "10", "11", "12") // restrict data to high school students

* convert string values into number labels
encode GENDER, gen(gender)
encode RACE, gen(race)
encode GRADE, gen(grade)
recode grade (1=9) (2=10) (3=11) (4=12)
drop GRADE RACE GENDER
rename ENROLLMENT enrol

/*
Now, I generate the enrolment statisitcs for students in every grade between 9 and 12 
I do this by collapsing the data by gender-race 
and then, reshaping that data to show enrolment as a cross-tabulation across race and gender
*/
forvalues i=9/12{ // loop over every grade
	preserve
	keep if grade==`i' // keep data for that grade
	collapse (sum) enrol, by(race gender) // collapse data by race-gender combination
	reshape wide enrol, i(race) j(gender) // enrolment as a cross-tabulation across race and gender
	mkmat enrol1, mat(A`i')
	mkmat enrol2, mat(B`i')
	mat C`i' = A`i' + B`i'
	mat D`i' = A`i', B`i', C`i' // total enrolment by race
	mat colnames D`i' = male female total
	mat rownames D`i' =   American_Indian_Alaskan_Native Asian African_American Hispanic Multiple_Ethinicity Native_Hawaiian_Pacific_Islander White
	restore
}

* Enrolment by race and gender for grade 9
matlist D9

* Enrolment by race and gender for grade 10
matlist D10

* Enrolment by race and gender for grade 11
matlist D11

* Enrolment by race and gender for grade 12
matlist D12