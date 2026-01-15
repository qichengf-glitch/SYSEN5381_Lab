# 📌 HOMEWORK

## Homework 1: Temporal Analyses

🕒 *Estimated Time: X hours*

---

## 📋 Homework Overview

Using your selected project dataset, measure and visualize change over time, adjusting for social controls. Recommend specific actions based on your findings.

In this homework, you are asked to conduct several analyses measuring and visualizing change over time in an outcome of interest using your selected project dataset. Please complete each of the following tasks, reporting (1) your fully commented code and (2) a concise written summary of your findings, including specific numbers from your analysis in the text.

Your challenge is to measure, visualize, and communicate that change over time in an effective manner. Your writing should be geared towards decision-makers (e.g., your supervisor, public officials, etc.). In your writing, prioritize clarity, transparency, and accuracy.

**Note**: This homework compiles work from 2-3 weekly LABS. Each LAB represents the next step of your project.

---

## 📝 Instructions

### Who?
Individual homework assignment - 1 per team member.

### What?
Answer each question in this homework. Complete all tasks and report your findings.

### Why?
This homework is a step-by-step checklist investigation of a big dataset of your choosing. Upon completion, you will have completed a big-data analysis on your own.

### What dataset?
You choose. You are strongly encouraged to use your project team's dataset, so that you can reuse your analyses in dashboards we build later. You must either (a) use one of the datasets in our course Github repository OR get your dataset approved by your instructor.

### How do I do this?
You can do it. This is a checklist of tasks. Don't overthink it - short, concise answers will do.

### Homework Formatting
Please submit your responses as a `.docx` file, containing all answers and R code. Please match the formatting of this Google Doc: [Homework Template](https://docs.google.com/document/d/1ySZnIlyu8rOCUkrKMODsgucDEKQO1BZCEQ49KRKsjqA/edit?usp=sharing)

---

## 🔍 Clarification: What methods should I use?

Use a combination of the following methods we learned to do a meaningful temporal analysis, and pair it with visualization:

- **🔹 Filtering**: Filter to certain subsets of data, to certain year ranges, etc. Compare results for one filter against another.

- **📏 Metrics**: Measure Change over Time using `mutate()`, `group_by()`, `summarize()`, and/or `reframe()`.

- **📈 Beta Coefficients**: Show an Effect with Beta Coefficients, controlling for time, and describe the beta coefficient.
  - Pro: Simple.
  - Con: Hard to get a highly predictive model from a big dataset. If so, do Iteration instead.

- **🎲 Simulation**: Show an Effect with Simulations, controlling for time, and simulate quantities of interest.

- **🔄 Iteration x Beta Coefficients**: Model an Effect of Interest many times, one per timestep, and compare the beta coefficients.

- **🔁 Iteration x Simulation**: Model an Effect of Interest many times, using one model per timestep, and compare simulated quantities of interest.

**🎯 Shared Goal, no matter what method**: Write out how you measured change over time, emphasizing great data communication.

**⚠️ Note**: Please skip introductions. Jump right to the meat of the issue, with no more than 1-2 sentences of background.

---

## ✅ Your Tasks

### ❓ Q1. [20 pts] Choose Your Outcome Variable

Select your primary outcome variable of interest, and use it for all subsequent questions.

**This variable must vary over time. It must be a time-series cross-sectional variable**, e.g. system usage among users (cross-sections) over months (time-series), education levels among counties (cross-sections) over years (time-series), etc.

Please report:

- **📌 [1 pt] What is your outcome variable of interest?**
  - Example: For education levels among counties annually, share of residents over age 25 with at least 1 year of college education or more.

- **📐 [1 pt] What are the units of your outcome variable?**
  - Example: For education levels among counties annually, percentage of residents, or perhaps rate per 1000 residents.

- **🏷️ [1 pt] Create a short name for your variable that will be instantly understood by an ordinary reader, not a specialist.**
  - Example: "Some college education or more."

- **📚 [1 pt] What is your data source?**
  - (1) Briefly summarize it, and (2) provide an APA reference for it, with a name, year, and link, at minimum.

- **🗂️ [1 pt] What is the unit of observation in your dataset?**
  - Example: For education levels among counties annually, a county-year.

- **🔢 [1 pt] How many observations are in your dataset?**
  - Example: How many county-years?

- **⏳ [1 pt] How many time-steps are there in your dataset?**
  - Example: How many unique years?

- **👥 [1 pt] How many unique groups (cross-sections) are in your dataset?**
  - Example: How many unique counties?

- **⚖️ [1 pt] Is your dataset balanced or unbalanced?**
  - Report the min, max, and average number of cross-sections per time step.
  - Balanced = even number of cross sections per time step
  - Unbalanced = some time steps have more cross sections than others.

- **❓ How much missing data is present in your outcome variable?**
  - Very common in socio-technical systems. Under 5% missing data is easy to deal with. If more than that:
    - (A) add scope conditions to narrow into a meaningful subset with less missing data OR
    - (B) pick a different variable and repeat these steps OR
    - (C) talk to your professor.
  - Please report:
    - **⚠️ [1 pt] Total share of missing values for the variable.**
    - **⚠️ [1 pt] Share of missing values per time-step.**
    - **⚠️ [1 pt] Max and min share of missing values among time-steps.**
    - **⚠️ [1 pt] Share of missing values per cross-section.**
    - **⚠️ [1 pt] Max and min share of missing values among cross-section.**

- **📍 [1 pt] What are the scope conditions of your analysis?**
  - Example: "I will only look at variable X from years 5 to 15 in region X because years 1-4 have lots of missing data (>35%) and counties in region Y have lots of missing data (>25%)" Other considerations might include "I will look at solar power but not wind, due to better data availability for solar, etc."

- **✍️ [5 pt] Summarize your outcome variable of interest in one paragraph for an ordinary reader, in concise, precise language.**
  - Be sure to briefly clarify and cite the data source, the unit of measurement, the unit of observation, the number of time-steps and cross-sections, the number of observations, and the share of missing data, as well as anything else that needs clarifying.

---

# 📤 To Submit

- For credit: Submit your responses as a `.docx` file, containing all answers and R code. Please match the formatting of the [Homework Template](https://docs.google.com/document/d/1ySZnIlyu8rOCUkrKMODsgucDEKQO1BZCEQ49KRKsjqA/edit?usp=sharing)

---

![](prep/icons.png)

---

← 🏠 [Back to Top](#HOMEWORK)
